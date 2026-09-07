# PocketMind

A native iPhone workspace for local language models, permission-controlled agents, and offline knowledge.

## Product

- **Chat:** private, streaming conversations with a downloaded GGUF model.
- **Work:** a bounded agent loop with independently controlled knowledge search, file listing/reading, file creation, and web search. Writes can require an explicit preview and approval.
- **Models:** curated mobile-size Gemma, Qwen, Liquid, Granite, Phi, Llama and SmolLM models, plus Hugging Face repository search and local GGUF import.
- **Knowledge:** import folders, text and PDFs; retrieve compressed passages with inspectable source citations. Download compressed Wikipedia ZIM archives directly from Kiwix, including English mini and full text editions.

## Development

Requires Xcode 26.1 or later, the iOS simulator runtime, and XcodeGen (`brew install xcodegen`). Run `./scripts/bootstrap.sh`, then open `PocketMind.xcodeproj`. Select your Apple development team to install on a physical iPhone. Simulator builds use CPU inference; devices use Metal.

The app targets iOS 18+. There is no hosted inference service, account requirement, or analytics. Models and knowledge archives download only when requested. Network access is needed for downloads and the optional web tools.

## Status

Active implementation. See [architecture](docs/architecture.md) for the boundaries and storage design. Build and validation instructions will be updated as implementation lands.

## Upstream projects

- [llama.cpp](https://github.com/ggml-org/llama.cpp): native GGUF inference (MIT).
- [libzim / Kiwix](https://github.com/kiwix/apple): compressed, indexed Wikipedia archives (GPL-3.0 dependencies).
- [Hugging Face Hub](https://huggingface.co/docs/hub/api): model discovery and downloads. Each model retains its own license; open weights do not necessarily mean OSI-approved open source.

PocketMind source is GPL-3.0-or-later. Model weights and Wikipedia content are separately licensed.
