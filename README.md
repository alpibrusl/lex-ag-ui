# lex-ag-ui

A Lex implementation of [AG-UI](https://docs.ag-ui.com) (the Agent-User
Interaction Protocol) — the event stream a Lex agent server emits so a
frontend can render live text, tool calls, and state without hand-rolled
polling.

There's no official Lex SDK for AG-UI (only Python/TypeScript), so this
package fills the same role `lex-fix` fills for FIX and `lex-agent` fills
for A2A: a thin, typed wrapper matching an external protocol's wire
format exactly, built on primitives this ecosystem already has.

## What's already there — no new runtime plumbing

- `lex-web`'s `stream.lex` has real SSE support (`event_stream`,
  `StreamResponse`), and `router.route_stream` / `dispatch_outcome` /
  `DStream` are fully wired (see `lex-web/examples/streaming_api.lex`).
- `lex-llm`'s `run_loop` already returns a lazy `Iter[Step]`
  (`lex-llm/src/agent.lex:110`) of token deltas and tool-call events
  (`lex-llm/src/delta.lex`).

The gap this package closes: nothing translates that `Iter[Step]` into
AG-UI's event shape, or serves it over SSE. `lex-oms-agent`'s
`a2a_agent.lex`, for example, currently drains the whole stream into one
collected response before replying — the live stream exists and gets
thrown away one layer up.

## What's in here

- **`src/event.lex`** — the `AguiEvent` ADT (core event set: `RUN_*`,
  `TEXT_MESSAGE_*`, `TOOL_CALL_*`, `STATE_*`, `CUSTOM`, `RAW`) plus a
  JSON encoder matching AG-UI's wire schema.
- **`src/bridge.lex`** — `from_llm_steps(Iter[d.Step], thread_id, run_id) -> Iter[ev.AguiEvent]`,
  the actual translation. **Not lazy end-to-end** — see below.
- **`src/sse.lex`** — `to_sse(Iter[AguiEvent]) -> stream.StreamResponse`,
  a one-line wrapper over `lex-web`'s existing `event_stream`.
- **`src/mount.lex`** — `add_to(router, path, run)`, the actual "one call
  to integrate AG-UI into any Lex agent server" entry point. `run` just
  needs to produce an `Iter[d.Step]` — works with `lex-llm`'s `run_loop`
  directly, or a hand-rolled equivalent, whether or not the caller uses
  `lex-agent`'s `AgentDef` at all.

## `lex test` does not actually gate on assertion failures — read this

Confirmed against `lex-cli`'s own source
(`crates/lex-cli/src/test_runner.rs`): `lex test` calls `run_all` and
only checks whether the call *raises a runtime error* — it discards
`run_all`'s return value entirely. The `count_failures(suite_pure())`
pattern `lex init` itself scaffolds (and every test file in this repo,
and `lex-oms`'s existing test suite, followed) **always reports "pass"
to `lex test`/`lex ci`, no matter how many assertions actually fail.**

This isn't theoretical — building this package's `from_llm_steps`, a
real bug (`RUN_FINISHED` was never appended after a normal `StepDone`)
shipped past `lex check --strict`, `lex fmt --check`, and `lex test`
all reporting green simultaneously. It only surfaced once caught
manually via `lex run tests/test_bridge.lex run_all` and inspecting the
returned count by hand.

Every `run_all` in this repo now forces a genuine runtime error
(`1 / 0` — confirmed to actually raise `integer division by zero` and
exit nonzero) when `count_failures(...) > 0`, so `lex test`/`lex ci`
are real gates here. This is worth fixing upstream in `lex-init`'s
scaffold and in any other repo using the old convention — `lex-oms`'s
already-merged `mifid_report` tests have the same silent-pass gap.

## Wire format caveat

Field names were verified against the AG-UI Go SDK reference docs
(`pkg.go.dev/.../ag-ui/.../core/events`) cross-checked against a second
independent source, **not** a byte-for-byte diff of `@ag-ui/core`'s
TypeScript source. Re-verify against that before wiring a production
frontend client (e.g. `@ag-ui/client`).

Only the *core* event set is modeled — Reasoning/Activity/Thinking event
families exist in the wider AG-UI spec but aren't implemented, because
`lex-llm`'s `Step`/`Delta` stream has no signal for them yet.

## Not lazy end-to-end — a real, deliberate tradeoff

`from_llm_steps` drains the whole input `Iter[d.Step]` via `list.fold`
before returning (wrapped back up with `iter.from_list`), rather than
staying lazy via `iter.unfold`. Two independent problems forced this:

1. `lex check --strict` flagged a `STACK_DEPTH` compiler warning on a
   self-recursive `iter.unfold` step function (needed to skip steps that
   produce zero events, e.g. `UsageDelta`) — every restructuring attempt
   produced the identical "path A depth 3, path B depth 2" mismatch.
2. More importantly: `lex-web`'s own benchmark server
   (`lex-web/bench/servers/lex_web_bench_stream.lex`) documents that in
   lex 0.9.4, the runtime's `BodyStream` sink drains `iter.from_list`-backed
   iterators correctly but **returns an empty body for `iter.unfold`-backed
   ones**. Shipping the lazy version would have silently produced empty
   SSE responses at runtime, not just a lint warning.

Practical effect: `RUN_STARTED` isn't sent until the whole lex-llm turn
completes, not as it starts. The wire behavior once sending begins is
unaffected (SSE frames still go out one at a time via chunked transfer,
sent by `net.serve_fn`'s streaming machinery) — this only affects
how early the first byte goes out. Re-check both issues against a newer
`lex` release before attempting true incremental streaming here.

## Known bridge limitations (v1)

- Tracks one open text span and one open tool-call span at a time — true
  concurrent tool calls in a single turn need a map keyed by
  `tool_call_id` instead.
- `TOOL_CALL_RESULT.content` is `"ok"`/`"error"`, not the tool's actual
  return payload — `lex-llm`'s `StepToolResult((Str, Bool))` only carries
  a success flag today.
- `TOOL_CALL_START.parentMessageId` is always `null` — `lex-llm`'s
  `Delta` stream doesn't associate a tool call with a text message.

## `lex-schema/json_value` has no `stringify`

`lex-agent/src/stream.lex` calls `jv.stringify`, but the current
`lex-schema` (0.9.3, as of this package's initial commit) doesn't export
one. `event.lex` hand-rolls its own `write_json` rather than depend on a
function that doesn't exist in the pinned version — worth reconciling
with `lex-schema` upstream at some point.

## Usage sketch

```lex
import "lex-llm/src/agent" as llm_agent
import "lex-ag-ui/src/bridge" as agui_bridge
import "lex-ag-ui/src/sse" as agui_sse
import "lex-web/src/router" as router

# inside a route_stream handler:
let steps := llm_agent.run_loop(agent, conversation)
let events := agui_bridge.from_llm_steps(steps, thread_id, run_id)
agui_sse.to_sse(events)
```

## Status

v1, unreleased. Built as phase 1 of a larger plan to stream
`lex-oms-agent` (and eventually every `lex-agent` persona) to
`lex-portal` over AG-UI instead of today's fetch-then-JSON polling. Not
yet wired into any agent server — see this repo's issues for the
integration work.
