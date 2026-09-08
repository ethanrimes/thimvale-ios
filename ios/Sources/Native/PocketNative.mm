#import "PocketNative.h"
#include <llama/llama.h>
#include <minja/chat-template.hpp>
#include <zim/archive.h>
#include <zim/search.h>
#include <zim/item.h>
#include <zim/error.h>
#include <atomic>
#include <climits>
#include <memory>
#include <vector>
#include <algorithm>
#include <mutex>
#include <chrono>
#include <os/proc.h>

static void PMError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"Thimvale.Native" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}

static std::string piece(const llama_vocab *vocab, llama_token token, bool special = false) {
    if (token < 0) return "";
    std::vector<char> bytes(128);
    int count = llama_token_to_piece(vocab, token, bytes.data(), (int)bytes.size(), 0, special);
    if (count < 0) { bytes.resize(-count); count = llama_token_to_piece(vocab, token, bytes.data(), (int)bytes.size(), 0, special); }
    return count > 0 ? std::string(bytes.data(), count) : "";
}

@implementation PMInference {
    llama_model *_model;
    llama_context *_context;
    std::atomic<bool> _cancelled;
    std::unique_ptr<minja::chat_template> _template;
    NSDictionary<NSString *, NSNumber *> *_generationStatistics;
    std::vector<llama_token> _cachedTokens;
}
- (instancetype)init {
    if ((self = [super init])) { _model = nullptr; _context = nullptr; _cancelled = false; _reusePromptCache = YES; }
    return self;
}
- (void)unload {
    std::vector<llama_token>().swap(_cachedTokens);
    _generationStatistics = @{};
    _template.reset();
    if (_context) { llama_free(_context); _context = nullptr; }
    if (_model) { llama_model_free(_model); _model = nullptr; }
}
- (void)dealloc { [self unload]; }
- (void)cancel { _cancelled.store(true); }
- (void)resetCancellation { _cancelled.store(false); }
- (NSDictionary<NSString *, NSNumber *> *)generationStatistics { return _generationStatistics ?: @{}; }
- (BOOL)loadModelAtPath:(NSString *)path contextSize:(int)contextSize error:(NSError **)error {
    [self unload];
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    const uint64_t bytes = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
    const size_t available = os_proc_available_memory();
    if (available > 0 && bytes + 384 * 1024 * 1024 > available) {
        PMError(error, @"This model needs more memory than iOS currently makes available. Close other apps or choose a smaller quantization.");
        return NO;
    }
#endif
    static std::once_flag initialized;
    std::call_once(initialized, [] {
        llama_backend_init();
        // Prevent prompts or generated text from entering OS logs.
        llama_log_set([](ggml_log_level, const char *, void *) {}, nullptr);
    });
    auto parameters = llama_model_default_params();
    parameters.load_mode = LLAMA_LOAD_MODE_MMAP;
    parameters.n_gpu_layers = 99;
#if TARGET_OS_SIMULATOR
    parameters.n_gpu_layers = 0;
#endif
    parameters.progress_callback = [](float, void *data) { return !static_cast<std::atomic<bool> *>(data)->load(); };
    parameters.progress_callback_user_data = &_cancelled;
    _model = llama_model_load_from_file(path.fileSystemRepresentation, parameters);
    if (!_model) { PMError(error, @"Could not load this GGUF. Check available memory and model compatibility."); return NO; }
    auto config = llama_context_default_params();
    config.n_ctx = std::min(std::max(contextSize, 512), llama_model_n_ctx_train(_model));
    config.n_batch = _batchSize > 0 ? std::clamp(_batchSize, 32, 512) : 256;
    config.n_ubatch = _microBatchSize > 0 ? std::clamp(_microBatchSize, 32, (int)config.n_batch) : std::min(128, (int)config.n_batch);
    config.n_threads = _threadCount > 0 ? std::clamp(_threadCount, 1, 8) : (int)std::max(1L, std::min(6L, (long)NSProcessInfo.processInfo.processorCount - 2));
    config.n_threads_batch = config.n_threads;
    config.abort_callback = [](void *data) { return static_cast<std::atomic<bool> *>(data)->load(); };
    config.abort_callback_data = &_cancelled;
    _context = llama_init_from_model(_model, config);
    if (!_context) { [self unload]; PMError(error, @"There is not enough memory to create the model context."); return NO; }
    try {
        const char *source = llama_model_chat_template(_model, nullptr);
        if (!source) throw std::runtime_error("This GGUF does not include a chat template. Choose an instruction-tuned model.");
        const auto *vocab = llama_model_get_vocab(_model);
        _template = std::make_unique<minja::chat_template>(source, piece(vocab, llama_vocab_bos(vocab), true), piece(vocab, llama_vocab_eos(vocab), true));
    } catch (const std::exception &e) {
        [self unload]; PMError(error, [NSString stringWithFormat:@"Unsupported chat template: %s", e.what()]); return NO;
    }
    return YES;
}
- (NSString *)generateMessages:(NSArray<NSDictionary<NSString *,NSString *> *> *)messages maxTokens:(int)maxTokens temperature:(float)temperature onToken:(void (^)(NSString *))onToken error:(NSError **)error {
    using Clock = std::chrono::steady_clock;
    const auto started = Clock::now();
    _generationStatistics = @{};
    if (!_model || !_context || !_template) { PMError(error, @"Select a downloaded model first."); return nil; }
    try {
        auto inputs = minja::chat_template_inputs();
        inputs.messages = json::array();
        for (NSDictionary *message in messages) {
            inputs.messages.push_back({{"role", [message[@"role"] UTF8String]}, {"content", [message[@"content"] UTF8String]}});
        }
        inputs.tools = json::array();
        inputs.extra_context = {{"enable_thinking", false}, {"thinking", false}};
        const auto *vocab = llama_model_get_vocab(_model);
        const int capacity = (int)llama_n_ctx(_context);
        maxTokens = std::clamp(maxTokens, 1, capacity / 2);
        std::vector<llama_token> tokens;
        // Drop complete historical user/assistant pairs while preserving the system prompt and latest input.
        for (;;) {
            std::string prompt = _template->apply(inputs);
            int size = -llama_tokenize(vocab, prompt.data(), (int)prompt.size(), nullptr, 0, true, true);
            if (size <= 0) throw std::runtime_error("The model could not tokenize the conversation.");
            if (size + maxTokens <= capacity) {
                tokens.resize(size);
                llama_tokenize(vocab, prompt.data(), (int)prompt.size(), tokens.data(), size, true, true);
                break;
            }
            if (inputs.messages.size() <= 3) throw std::runtime_error("This message and its evidence exceed the model context. Use a shorter question or fewer sources.");
            inputs.messages.erase(inputs.messages.begin() + 1, inputs.messages.begin() + 3);
        }
        auto memory = llama_get_memory(_context);
        size_t reused = 0;
        if (_reusePromptCache) {
            while (reused < tokens.size() && reused < _cachedTokens.size() && tokens[reused] == _cachedTokens[reused]) ++reused;
            // Re-evaluate one token for fresh logits when the entire prompt is already cached.
            if (reused == tokens.size()) --reused;
            if (reused > 0 && llama_memory_seq_pos_max(memory, 0) != (llama_pos)_cachedTokens.size() - 1) reused = 0;
            // A sliding-window cache may have evicted keys needed by an earlier position.
            // Trimming cannot restore those keys. Only append when that history is incomplete.
            if (reused > 0 && reused < _cachedTokens.size() && llama_memory_seq_pos_min(memory, 0) > 0) reused = 0;
            // A recurrent/hybrid model may not support trimming its historical state.
            // Append-only continuations need no trim; any failed rollback gets a clean prefill.
            if (reused > 0 && reused < _cachedTokens.size() && !llama_memory_seq_rm(memory, 0, (llama_pos)reused, -1)) reused = 0;
        }
        if (reused == 0) llama_memory_clear(memory, true);
        _cachedTokens.assign(tokens.begin(), tokens.begin() + reused);
        const int batchSize = (int)llama_n_batch(_context);
        auto batch = llama_batch_init(batchSize, 0, 1);
        struct BatchGuard { llama_batch b; ~BatchGuard() { llama_batch_free(b); } } batchGuard{batch};
        auto fill = [&](const llama_token *values, int size, int position, bool logits = true) {
            batch.n_tokens = size;
            for (int i = 0; i < size; ++i) {
                batch.token[i] = values[i]; batch.pos[i] = position + i;
                batch.n_seq_id[i] = 1; batch.seq_id[i][0] = 0;
                batch.logits[i] = logits && (i == size - 1);
            }
        };
        for (int offset = (int)reused; offset < tokens.size(); offset += batchSize) {
            if (_cancelled.load()) throw std::runtime_error("Generation stopped.");
            int count = std::min(batchSize, (int)tokens.size() - offset);
            // Intermediate prompt batches do not need a vocabulary projection or CPU logits transfer.
            fill(tokens.data() + offset, count, offset, offset + count == tokens.size());
            if (llama_decode(_context, batch) != 0) throw std::runtime_error(_cancelled.load() ? "Generation stopped." : "The model could not process this prompt.");
            _cachedTokens.insert(_cachedTokens.end(), tokens.begin() + offset, tokens.begin() + offset + count);
        }
        llama_sampler *sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
        struct SamplerGuard { llama_sampler *s; ~SamplerGuard() { llama_sampler_free(s); } } samplerGuard{sampler};
        llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.1f, 0, 0));
        if (temperature <= 0) {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9f, 1));
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(std::max(0.05f, temperature)));
            uint32_t seed = LLAMA_DEFAULT_SEED;
#if DEBUG && TARGET_OS_SIMULATOR
            // Real inference, reproducible sampling in isolated regression sessions only.
            NSString *testSession = NSProcessInfo.processInfo.environment[@"THIMVALE_TEST_SESSION"];
            if (testSession.length && [[NSUUID alloc] initWithUUIDString:testSession]) seed = 42;
#endif
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(seed));
        }
        NSMutableString *output = [NSMutableString new];
        std::string pending;
        const auto promptDone = Clock::now();
        double firstTokenMS = 0;
        int emitted = 0;
        for (int generated = 0; generated < maxTokens; ++generated) {
            if (_cancelled.load()) throw std::runtime_error("Generation stopped.");
            llama_token token = llama_sampler_sample(sampler, _context, -1);
            if (llama_vocab_is_eog(vocab, token)) break;
            if (emitted++ == 0) firstTokenMS = std::chrono::duration<double, std::milli>(Clock::now() - started).count();
            pending += piece(vocab, token);
            NSString *chunk = [[NSString alloc] initWithBytes:pending.data() length:pending.size() encoding:NSUTF8StringEncoding];
            if (chunk) { [output appendString:chunk]; onToken(chunk); pending.clear(); }
            fill(&token, 1, (int)tokens.size() + generated);
            if (llama_decode(_context, batch) != 0) throw std::runtime_error(_cancelled.load() ? "Generation stopped." : "Generation failed. Try a smaller model or context.");
            _cachedTokens.push_back(token);
        }
        const auto ended = Clock::now();
        _generationStatistics = @{
            @"promptTokens": @(tokens.size()), @"generatedTokens": @(emitted),
            @"reusedTokens": @(reused),
            @"promptMS": @(std::chrono::duration<double, std::milli>(promptDone - started).count()),
            @"firstTokenMS": @(firstTokenMS),
            @"decodeMS": @(std::chrono::duration<double, std::milli>(ended - promptDone).count()),
            @"totalMS": @(std::chrono::duration<double, std::milli>(ended - started).count())
        };
        return output;
    } catch (const std::exception &e) {
        // A failed/aborted decode may have partially changed the native state.
        _cachedTokens.clear();
        llama_memory_clear(llama_get_memory(_context), true);
        PMError(error, [NSString stringWithUTF8String:e.what()]); return nil;
    }
}
@end

@implementation PMArchive {
    std::unique_ptr<zim::Archive> _archive;
    std::unique_ptr<zim::Searcher> _searcher;
}
- (instancetype)initWithPath:(NSString *)path error:(NSError **)error {
    if ((self = [super init])) {
        try {
            _archive = std::make_unique<zim::Archive>(path.fileSystemRepresentation);
            if (!_archive->hasFulltextIndex()) throw std::runtime_error("This ZIM has no full-text index. Download an indexed Wikipedia edition.");
            _searcher = std::make_unique<zim::Searcher>(*_archive);
            _searcher->setVerbose(false);
        } catch (const std::exception &e) { PMError(error, [NSString stringWithUTF8String:e.what()]); return nil; }
    }
    return self;
}
- (NSUInteger)articleCount { return _archive ? _archive->getArticleCount() : 0; }
- (NSArray<NSDictionary<NSString *,NSString *> *> *)browse:(NSString *)query offset:(int)offset limit:(int)limit error:(NSError **)error {
    try {
        offset = std::clamp(offset, 0, INT_MAX - 100);
        limit = std::clamp(limit, 1, 100);
        NSMutableArray *output = [NSMutableArray new];
        if (query.length == 0) {
            for (auto entry : _archive->iterByTitle().offset(offset, limit)) {
                [output addObject:@{@"title": [NSString stringWithUTF8String:entry.getTitle().c_str()],
                                    @"path": [NSString stringWithUTF8String:entry.getPath().c_str()]}];
            }
        } else {
            auto search = _searcher->search(zim::Query(query.UTF8String));
            auto results = search.getResults(offset, limit);
            for (auto it = results.begin(); it != results.end(); ++it) {
                [output addObject:@{@"title": [NSString stringWithUTF8String:it.getTitle().c_str()],
                                    @"path": [NSString stringWithUTF8String:it.getPath().c_str()],
                                    @"snippet": [NSString stringWithUTF8String:it.getSnippet().c_str()]}];
            }
        }
        return output;
    } catch (const std::exception &e) { PMError(error, [NSString stringWithUTF8String:e.what()]); return nil; }
}
- (NSDictionary<NSString *,NSString *> *)articleAtPath:(NSString *)path error:(NSError **)error {
    try {
        auto item = _archive->getEntryByPath(path.UTF8String).getItem(true);
        auto mime = item.getMimetype();
        if (mime.find("text/html") != 0 && mime != "application/xhtml+xml")
            throw std::runtime_error("This link is not a readable article.");
        if (item.getSize() > 4 * 1024 * 1024)
            throw std::runtime_error("This article exceeds the reader's 4 MB page limit.");
        auto blob = item.getData();
        NSString *html = [[NSString alloc] initWithBytes:blob.data() length:blob.size() encoding:NSUTF8StringEncoding];
        if (!html) throw std::runtime_error("This article is not valid UTF-8 text.");
        return @{@"title": [NSString stringWithUTF8String:item.getTitle().c_str()],
                 @"path": [NSString stringWithUTF8String:item.getPath().c_str()], @"html": html};
    } catch (const zim::EntryNotFound &) {
        PMError(error, @"This page isn't included in this pack. Try another downloaded edition."); return nil;
    } catch (const std::exception &e) { PMError(error, [NSString stringWithUTF8String:e.what()]); return nil; }
}
- (NSArray<NSDictionary<NSString *,NSString *> *> *)search:(NSString *)query limit:(int)limit error:(NSError **)error {
    try {
        auto search = _searcher->search(zim::Query(query.UTF8String));
        auto results = search.getResults(0, std::clamp(limit, 1, 12));
        NSMutableArray *output = [NSMutableArray new];
        for (auto it = results.begin(); it != results.end(); ++it) {
            auto item = it->getItem(true);
            if (item.getSize() > 4 * 1024 * 1024) continue;
            auto blob = item.getData();
            NSString *html = [[NSString alloc] initWithBytes:blob.data() length:blob.size() encoding:NSUTF8StringEncoding];
            if (!html) continue;
            [output addObject:@{@"title": [NSString stringWithUTF8String:it.getTitle().c_str()],
                                @"path": [NSString stringWithUTF8String:it.getPath().c_str()],
                                @"html": html,
                                @"snippet": [NSString stringWithUTF8String:it.getSnippet().c_str()]}];
        }
        return output;
    } catch (const std::exception &e) { PMError(error, [NSString stringWithUTF8String:e.what()]); return nil; }
}
@end
