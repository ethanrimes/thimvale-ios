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

Both modes display actual emitted text in an automatically expanded **Model output** card. This includes model-produced tool JSON in Work. A completed generation can be expanded again to inspect its output; the final answer remains in the conversation below. Answer-only citation recovery streams through the same path. There is no fabricated reasoning transcript or simulated production activity.

Each executed Work tool gets a separate card with its name, arguments, **Checking permissions / Awaiting approval / Running / Completed / Failed / Stopped** state, elapsed time, and result or error. Result previews are bounded to 6000 characters. Fast local calls may finish in one UI frame; their completed event and duration remain visible.

Partial JSON never executes. Parsing occurs only after a complete generation, and existing mode, approval, folder, permission-recheck, and call-budget checks still apply. Output and result previews are plain text rather than actionable Markdown. Chat still has no tool access.

The ordered token stream is drained before a round completes. Stopping retains partial output and marks the event stopped; old tokens cannot append to a later round. Activity, tool arguments, and result previews are saved locally with the conversation. Share message shares the final answer, not the activity transcript. Older conversations without structured events still load. Saved active events are marked stopped after process restart.

Stop does not undo a tool that already completed. In particular, a successfully created file keeps its completed result in the feed even if the following response is stopped.

## Validation approach

The real GGUF test checks preload, weight reuse, cancellation, unload, reload, and recovery after a failed model switch. Real-model UI tests check visible output before completion, Stop, memory state across new conversations/background/relaunch, and automatic reload on send.

Separately labelled scripted integration tests control timing to verify partial-token delivery, approval ordering, tool results, idle expiry, rapid switching, and stale-token protection deterministically. They are test doubles, not evidence of any model's tool-selection quality; the shipped app always uses the native runtime.
