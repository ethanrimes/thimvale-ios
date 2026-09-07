# Model memory and live activity

## Memory lifetime

- Choosing a downloaded model starts loading its weights immediately. The picker reports **Loading into memory**, **In memory**, or a load error with Retry.
- Chat, Work, tool rounds, and new conversations reuse the selected weights. Sending during preload waits for that same load instead of starting another one.
- Weights and inference context are released when the app enters the background, on a memory warning, when switching/deleting the selected model, or after **five minutes** without model use or typing in the composer. The idle timer is paused for an entire request, including tool execution and approval waits.
- Returning to the foreground does not eagerly reload an unloaded model. The next send loads it automatically; choosing a model again also preloads it. Downloaded model files and conversations remain on disk.
- Process termination lets iOS reclaim all process memory. This is not a promise to keep weights alive after iOS closes the app.

`ModelSession` owns the lifecycle; `InferenceService` serializes native operations. Cancellation is scoped to each queued operation so that a cancelled preload cannot cancel a subsequent selection. A failed replacement clears the old cache identity. These changes cache weights, **not the conversation's KV/prompt cache**: each generation still reconstructs its prompt within the existing 4096-token context.

Background GPU work is restricted by iOS; inference is stopped before queued model teardown. See [Apple's Metal background guidance](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background). GPU teardown timing and memory pressure still need signed physical-iPhone validation; simulator inference uses CPU.

## Live activity

Both modes stream the answer directly into the conversation, using the same width and typography as a finished reply, without a nested scrolling block. Raw generation transcripts are available under the collapsed **Model details** disclosure, including tool JSON and any emitted reasoning markers. Unfinished tool JSON and explicit unfinished `<think>` sections are not presented as the answer. Answer-only citation recovery streams through the same path. There is no fabricated reasoning transcript or simulated production activity.

Each executed Work tool gets a compact, borderless terminal-style row: status glyph, monospaced tool name, query or file target, **Checking permissions / Awaiting approval / Running / Completed / Failed / Stopped** state, and elapsed time. Tap a row for full arguments and results; they do not auto-expand. Result previews remain bounded to 6000 characters. Fast local calls may finish in one UI frame; their completed event and duration remain visible. The separate approval sheet still shows the complete proposed action before consent.

Citation numbers such as **[1]** are tappable inside both a streaming and a completed answer. Only IDs in that message's actual returned evidence become local source links; unknown or unfinished references remain text, and inline code is not rewritten. A tap opens the original passage inspector, not a website. The full deduplicated **Sources** list stays collapsed at the end and expands on request. Models that omit citations still show the missing-citation notice and expandable retrieved sources; the app does not invent inline attribution.

Partial JSON never executes. Parsing occurs only after a complete generation, and existing mode, approval, folder, permission-recheck, and call-budget checks still apply. Output and result previews are plain text rather than actionable Markdown. Chat still has no tool access.

The ordered token stream is drained before a round completes. Stopping retains partial output and marks the event stopped; old tokens cannot append to a later round. Activity, tool arguments, and result previews are saved locally with the conversation. Share message shares the final answer, not the activity transcript. Older conversations without structured events still load. Saved active events are marked stopped after process restart.

Stop does not undo a tool that already completed. In particular, a successfully created file keeps its completed result in the feed even if the following response is stopped.

## Validation approach

The real GGUF test checks preload, weight reuse, cancellation, unload, reload, and recovery after a failed model switch. Real-model UI tests check visible output before completion, Stop, memory state across new conversations/background/relaunch, and automatic reload on send.

Separately labelled scripted integration tests control timing to verify partial-token delivery, approval ordering, tool results, idle expiry, rapid switching, and stale-token protection deterministically. They are test doubles, not evidence of any model's tool-selection quality; the shipped app always uses the native runtime.
