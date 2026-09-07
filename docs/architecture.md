# Architecture and constraints

PocketMind is a SwiftUI iOS app. Native inference runs off the main actor through a llama.cpp bridge. A model is downloaded and validated before it becomes selectable; the app never replaces inference with a canned response.

## Capabilities

Chat cannot invoke tools. Work has a bounded action loop. Tool permissions are checked at execution, not merely described in the prompt. The read and write capabilities are independent. Models receive opaque folder identifiers, not arbitrary system paths. iOS grants access only to user-selected folders through security-scoped bookmarks; access can be revoked. File creation never overwrites an existing file. Knowledge and web results are untrusted evidence, with source identifiers retained separately from model output.

## Retrieval

Imported documents are chunked, deduplicated, compressed, and indexed in SQLite FTS5. English sentence embeddings from Apple's NaturalLanguage framework are sign-quantized to one bit per dimension where the embedding resource is available. This is lossy: it reduces vector bytes by 32x relative to Float32, not total database size. Lexical retrieval remains available if the device lacks the embedding resource. Local retrieval blends semantic similarity and lexical candidates.

Wikipedia uses Kiwix's existing compressed ZIM corpus and embedded full-text index. This avoids expanding tens of gigabytes of encyclopedia text or constructing millions of vectors on a phone. Retrieved passages can be embedded on device and reranked; the corpus remains randomly accessible offline. Mini editions contain abridged articles. Full text/no-picture editions preserve full articles and are substantially larger. Catalog sizes must come from current upstream metadata, not optimistic estimates.

## Scope

Text generation only in the first release, even for multimodal model families. GGUF compatibility depends on the pinned llama.cpp runtime and device memory. No arbitrary shell, cross-app filesystem access, silent background agent execution, or unlimited tool loop. Web access transmits only the explicit tool query; users can disable it independently.

## Validation

Tests must exercise capability denial, approval, traversal/symlink boundaries, retrieval/citation provenance, compression round trips, agent termination, download validation, and actual inference with a small real model. Simulator verification does not establish physical iPhone speed, battery consumption, or memory stability.
