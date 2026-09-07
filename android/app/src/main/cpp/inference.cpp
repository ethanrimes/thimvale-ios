#include <jni.h>
#include <llama.h>
#include <minja/chat-template.hpp>
#include <atomic>
#include <algorithm>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

struct Engine {
    llama_model *model = nullptr;
    llama_context *context = nullptr;
    std::unique_ptr<minja::chat_template> chat;
    std::atomic<bool> cancelled{false};
    void unload() {
        chat.reset();
        if (context) llama_free(context);
        if (model) llama_model_free(model);
        context = nullptr; model = nullptr;
    }
    ~Engine() { unload(); }
};
static Engine *engine(jlong handle) { return reinterpret_cast<Engine *>(handle); }
static std::string bytes(JNIEnv *env, jbyteArray value) {
    std::string result(env->GetArrayLength(value), '\0');
    env->GetByteArrayRegion(value, 0, result.size(), reinterpret_cast<jbyte *>(result.data()));
    return result;
}
static jbyteArray array(JNIEnv *env, const std::string &value) {
    auto result = env->NewByteArray(value.size());
    env->SetByteArrayRegion(result, 0, value.size(), reinterpret_cast<const jbyte *>(value.data()));
    return result;
}
static void fail(JNIEnv *env, const char *message) {
    env->ThrowNew(env->FindClass("java/lang/IllegalStateException"), message);
}
static std::string piece(const llama_vocab *vocab, llama_token token, bool special = false) {
    if (token < 0) return "";
    std::vector<char> buffer(128);
    int size = llama_token_to_piece(vocab, token, buffer.data(), buffer.size(), 0, special);
    if (size < 0) { buffer.resize(-size); size = llama_token_to_piece(vocab, token, buffer.data(), buffer.size(), 0, special); }
    return size > 0 ? std::string(buffer.data(), size) : "";
}
extern "C" JNIEXPORT jlong JNICALL Java_com_ethanrimes_thimvale_NativeEngine_create(JNIEnv *, jobject) {
    static std::once_flag once;
    std::call_once(once, [] {
        llama_backend_init();
        llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
    });
    return reinterpret_cast<jlong>(new Engine());
}
extern "C" JNIEXPORT void JNICALL Java_com_ethanrimes_thimvale_NativeEngine_cancel(JNIEnv *, jobject, jlong h) { engine(h)->cancelled = true; }
extern "C" JNIEXPORT void JNICALL Java_com_ethanrimes_thimvale_NativeEngine_reset(JNIEnv *, jobject, jlong h) { engine(h)->cancelled = false; }
extern "C" JNIEXPORT void JNICALL Java_com_ethanrimes_thimvale_NativeEngine_unload(JNIEnv *, jobject, jlong h) { engine(h)->unload(); }
extern "C" JNIEXPORT void JNICALL Java_com_ethanrimes_thimvale_NativeEngine_load(JNIEnv *env, jobject, jlong h, jbyteArray path) {
    auto *e = engine(h);
    e->unload();
    try {
        auto params = llama_model_default_params();
        params.n_gpu_layers = 0; // Portable CPU baseline. No unsupported GPU claims.
        params.load_mode = LLAMA_LOAD_MODE_MMAP;
        params.progress_callback = [](float, void *p) { return !static_cast<Engine *>(p)->cancelled.load(); };
        params.progress_callback_user_data = e;
        e->model = llama_model_load_from_file(bytes(env, path).c_str(), params);
        if (!e->model) throw std::runtime_error("Could not load this GGUF. Check memory and model compatibility.");
        auto config = llama_context_default_params();
        config.n_ctx = std::min(4096, llama_model_n_ctx_train(e->model));
        config.n_batch = 256; config.n_ubatch = 128;
        config.n_threads = std::clamp(static_cast<int>(std::thread::hardware_concurrency()) - 2, 1, 6);
        config.n_threads_batch = config.n_threads;
        config.abort_callback = [](void *p) { return static_cast<Engine *>(p)->cancelled.load(); };
        config.abort_callback_data = e;
        e->context = llama_init_from_model(e->model, config);
        if (!e->context) throw std::runtime_error("Not enough memory for this model context.");
        auto source = llama_model_chat_template(e->model, nullptr);
        if (!source) throw std::runtime_error("This GGUF has no chat template. Choose an instruction-tuned model.");
        auto vocab = llama_model_get_vocab(e->model);
        e->chat = std::make_unique<minja::chat_template>(source, piece(vocab, llama_vocab_bos(vocab), true), piece(vocab, llama_vocab_eos(vocab), true));
    } catch (const std::exception &error) { e->unload(); fail(env, error.what()); }
}
extern "C" JNIEXPORT jbyteArray JNICALL Java_com_ethanrimes_thimvale_NativeEngine_generate(JNIEnv *env, jobject, jlong h, jbyteArray messages, jint limit, jobject callback) {
    auto *e = engine(h);
    try {
        if (!e->context || !e->chat) throw std::runtime_error("Select a downloaded model first.");
        auto input = minja::chat_template_inputs();
        input.messages = json::parse(bytes(env, messages));
        input.tools = json::array();
        input.extra_context = {{"enable_thinking", false}, {"thinking", false}};
        auto vocab = llama_model_get_vocab(e->model);
        int maxTokens = std::clamp(static_cast<int>(limit), 1, static_cast<int>(llama_n_ctx(e->context)) / 2);
        std::vector<llama_token> tokens;
        for (;;) {
            auto prompt = e->chat->apply(input);
            int size = -llama_tokenize(vocab, prompt.data(), prompt.size(), nullptr, 0, true, true);
            if (size <= 0) throw std::runtime_error("Could not tokenize this conversation.");
            if (size + maxTokens <= llama_n_ctx(e->context)) {
                tokens.resize(size);
                llama_tokenize(vocab, prompt.data(), prompt.size(), tokens.data(), size, true, true);
                break;
            }
            if (input.messages.size() <= 3) throw std::runtime_error("The message and evidence exceed the model context. Try a shorter question.");
            input.messages.erase(input.messages.begin() + 1, input.messages.begin() + 3);
        }
        llama_memory_clear(llama_get_memory(e->context), true);
        auto batch = llama_batch_init(256, 0, 1);
        struct BatchGuard { llama_batch b; ~BatchGuard() { llama_batch_free(b); } } guard{batch};
        auto decode = [&](const llama_token *values, int count, int position) {
            if (e->cancelled) throw std::runtime_error("Generation stopped.");
            batch.n_tokens = count;
            for (int i = 0; i < count; ++i) {
                batch.token[i] = values[i]; batch.pos[i] = position + i;
                batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0; batch.logits[i] = (i == count - 1);
            }
            if (llama_decode(e->context, batch) != 0) throw std::runtime_error(e->cancelled ? "Generation stopped." : "Local inference failed. Try a smaller model.");
        };
        for (int offset = 0; offset < tokens.size(); offset += 256) decode(tokens.data() + offset, std::min(256, static_cast<int>(tokens.size()) - offset), offset);
        auto sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
        struct SamplerGuard { llama_sampler *s; ~SamplerGuard() { llama_sampler_free(s); } } sampleGuard{sampler};
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(.9f, 1));
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(.6f));
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(42));
        auto method = env->GetMethodID(env->GetObjectClass(callback), "onBytes", "([B)V");
        std::string output;
        for (int i = 0; i < maxTokens; ++i) {
            if (e->cancelled) throw std::runtime_error("Generation stopped.");
            auto token = llama_sampler_sample(sampler, e->context, -1);
            if (llama_vocab_is_eog(vocab, token)) break;
            output += piece(vocab, token);
            auto data = array(env, output);
            env->CallVoidMethod(callback, method, data);
            env->DeleteLocalRef(data);
            if (env->ExceptionCheck()) return nullptr;
            decode(&token, 1, tokens.size() + i);
        }
        return array(env, output);
    } catch (const std::exception &error) { fail(env, error.what()); return nullptr; }
}
