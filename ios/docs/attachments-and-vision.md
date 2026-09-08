# Chat attachments and image input

## Using it

1. Tap the paperclip beside the chat field. Select one or more files in Apple's Files picker, then Open. JPEG/PNG/HEIC images can be selected there too.
2. Tap an attachment chip to preview it; use its × to remove it before sending. Type a question, or send the files alone to request a description.
3. Text files supply source-numbered context in Chat and Work. Inline citations open the original excerpt. Long files use relevant passages, not the entire file.
4. For images, choose a Vision model in Models. Download the model weights, then its matching **vision file** in model details. Imported models can use “Import matching vision file.” Images are not accepted for a send until that file exists; compatibility is checked by the native engine.
5. Dismiss the chat keyboard with Done, a tap in the transcript, or an interactive scroll. The draft is retained.

The system picker can show On My iPhone, iCloud Drive, and installed file providers. It does not grant access to other apps' private sandboxes. Thimvale's Documents/Exports folder is shared with Files; its model weights, chats, and knowledge database live in private Application Support. Xcode's generated plist omitted `UIFileSharingEnabled` despite the build setting, so that Boolean is now supplied by `Config/App-Info.plist` and tested in the built app.

## Limits and privacy

- Up to six files per conversation, including at most three images. Each source file is limited to 25 MB.
- UTF-8 text, Markdown, CSV, JSON, HTML, common source-code formats, and PDFs with selectable text are supported. A PDF is limited to 200 pages; extracted text is limited to 100 KB per attachment. Larger text belongs in Knowledge. Scanned PDFs need selectable text or separately attached page images.
- Images are downsampled to at most 1024 pixels on the longer side, re-encoded as JPEG (at most 1.5 MB), and stripped of source metadata. Only the first image/frame is used for animated or multi-image files. There is no audio/video input or camera capture.
- Attachments are snapshots saved with the chat after sending. Moving/deleting the original does not break the conversation. Pending attachments are not persisted across termination. Deleting the chat deletes its stored attachment copies with it.
- Attachments never add documents to the knowledge index, create bookmarks, or change read/write/web permissions. Untrusted source instructions cannot change the permission policy enforced by the app. Work can still use separately enabled tools to fulfill the user's request; turn web search off if no network tools are wanted.
- Image encoders consume additional RAM and computation. Image preprocessing and native encoding must finish their current bounded operation before cancellation can complete. Backgrounding, memory pressure, and the existing five-minute idle timeout release both the text model and vision encoder. The next image request reloads them.

## Catalog and download behavior

Nine curated entries are marked Vision: Qwen 3.5 0.8B/2B/4B/9B, Gemma 3 4B, Gemma 4 E2B/E4B, Ministral 3 3B, and SmolVLM 256M. These are model capabilities, not a claim that every variant runs within every iPhone's memory limits. Gemma 3 1B, Phi 4 Mini, and text MiniCPM5 are not labeled as vision models.

Custom Hugging Face/imported models remain “Vision unverified” until actual image inference succeeds. Finding an mmproj file alone cannot establish that it contains a supported vision encoder. Weight and projector lists are separate; new model downloads retain the repository revision so a subsequent projector lookup stays on the same commit. Legacy/imported weights without revision metadata need a matching file chosen by the user. Projectors use the same resumable background transfer, size verification, and SHA-256 checks as models. A wrong projector produces an error without silently discarding the image.

The catalog addition is [SmolVLM 256M](https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF): Q8 weights plus its F16 vision file total 365,086,144 bytes. Other capability sources: [Qwen 3.5](https://huggingface.co/Qwen/Qwen3.5-0.8B), [Gemma 3](https://huggingface.co/ggml-org/gemma-3-4b-it-GGUF), [Gemma 4](https://huggingface.co/google/gemma-4-E2B-it-qat-q4_0-gguf), [Ministral 3](https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512).

## Validation

`ChatAttachmentTests` covers real UTF-8/HTML/PDF/image decoding, malformed/empty/oversized input, snapshot persistence, source identity, multi-file coverage, permission isolation, and draft handling. Scripted inference is used only for deterministic prompt/permission inspection. The actual GGUF tests exercise image pixels through MTMD and the app's import/send/lifecycle path. Identical questions with red versus blue image data test that answers depend on the pixels. A real Liquid text-model test answers an attached arrival-code question without any tool grants.

`scripts/fetch-vision-test-assets.sh` pins and checks SmolVLM model/projector hashes for the ordinary cloud gate. `--qwen` additionally fetches the optional local Qwen 3.5 0.8B Q4_K_M/F16 pair, used to exercise hybrid state and M-RoPE positions. Neither weights nor sample images are bundled in the release app. The adapter preserves SmolVLM's published chat template while translating its unsupported `capitalize` filter to minja's equivalent string method.

Simulator UI tests exercise the real multi-select Files picker, previews/removal, keyboard Done/cancel/tap dismissal, and the Vision filter. Passing these targeted fixtures is not a general image-accuracy benchmark or a physical-iPhone performance claim. Android shares catalog metadata but does not yet implement this iOS vision/attachment path.
