# lex-ag-ui — bridge lex-llm's Step/Delta stream into AG-UI events.
#
# lex-llm's `run_loop` yields a lazy `Iter[d.Step]`
# (lex-llm/src/agent.lex:110), where
#   Step  = StepDelta(Delta) | StepToolExec((Str, Str)) | StepToolResult((Str, Bool)) | StepDone(Message)
#   Delta = TextChunk(Str) | ToolCallBegin((Str, Str)) | ToolArgChunk((Str, Str)) | FinishDelta(Str) | UsageDelta(...)
# (lex-llm/src/delta.lex:16-18). `from_llm_steps` maps that onto the
# smallest correct AG-UI sequence: RUN_STARTED, a TEXT_MESSAGE_START /
# CONTENT* / END triad per text span, a TOOL_CALL_START / ARGS* / END
# span per tool call (closed at StepToolExec, matching when lex-llm's
# own loop considers the call's arguments complete), a TOOL_CALL_RESULT
# once StepToolResult arrives, and RUN_FINISHED at StepDone.
#
# NOT lazy end-to-end, and that's deliberate, not an oversight: this
# materialises the full event list via `list.fold` and wraps it with
# `iter.from_list` rather than `iter.unfold`. Precedent + reason, straight
# from lex-web's own benchmark server (lex-web/bench/servers/lex_web_bench_stream.lex):
# in lex 0.9.4 (matches this package's 0.10.7 pin -- unconfirmed whether
# it's since been fixed), the runtime's BodyStream sink drains
# `iter.from_list`-backed iterators correctly but returns an EMPTY body
# for `iter.unfold`-backed ones. A first draft of this file used
# `iter.unfold` for the lazy skip-ahead-past-empty-steps loop; besides
# tripping `lex check --strict`'s STACK_DEPTH checker on the self-recursive
# unfold step (a separate, likely-unrelated compiler limitation), it would
# have silently shipped an empty SSE response at runtime. Re-check both
# issues against a newer lex release before attempting true incremental
# streaming here -- the wire behavior (chunked transfer, sent frame by
# frame) is unaffected either way; what's lost is emitting RUN_STARTED
# before the whole lex-llm turn finishes.
#
# Known limitations (v1, honest about what lex-llm gives us):
#   - Only one open text span and one open tool-call span are tracked
#     at a time -- true concurrent/parallel tool calls in one turn
#     would need a map keyed by tool_call_id instead of a single slot.
#   - StepToolResult((Str, Bool)) carries a success flag, not the tool's
#     actual return payload, so TOOL_CALL_RESULT.content is a
#     placeholder ("ok"/"error") until lex-llm's Step exposes the real
#     result. Downstream consumers should treat it as a status hint,
#     not the tool's answer.
#   - ToolCallStart.parentMessageId is always None -- lex-llm's Delta
#     stream doesn't associate a tool call with a specific text message.
#
# Effects: none. `iter.to_list`/`iter.from_list` are pure per lex-lang's
# builtin signatures; whatever effects produced the input `steps` iterator
# already fired by the time this function runs.

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.iter" as iter

import "lex-llm/src/delta" as d

import "./event" as ev

type BridgeState = { in_text :: Option[Str], in_tool :: Option[Str], thread_id :: Str, run_id :: Str, counter :: Int }

type StepOutcome = { events :: List[ev.AguiEvent], st :: BridgeState, is_final :: Bool }

type FoldAcc = { events :: List[ev.AguiEvent], st :: BridgeState, done :: Bool }

fn fresh_id(st :: BridgeState, prefix :: Str) -> (Str, BridgeState) {
  let id := str.concat(prefix, str.concat("_", int.to_str(st.counter)))
  (id, { in_text: st.in_text, in_tool: st.in_tool, thread_id: st.thread_id, run_id: st.run_id, counter: st.counter + 1 })
}

fn with_text(st :: BridgeState, v :: Option[Str]) -> BridgeState {
  { in_text: v, in_tool: st.in_tool, thread_id: st.thread_id, run_id: st.run_id, counter: st.counter }
}

fn with_tool(st :: BridgeState, v :: Option[Str]) -> BridgeState {
  { in_text: st.in_text, in_tool: v, thread_id: st.thread_id, run_id: st.run_id, counter: st.counter }
}

fn no_events() -> List[ev.AguiEvent] {
  []
}

fn run_finished_event(st :: BridgeState) -> ev.AguiEvent {
  ev.RunFinished({ thread_id: st.thread_id, run_id: st.run_id })
}

fn fst2[A, B](p :: (A, B)) -> A {
  match p {
    (a, _) => a,
  }
}

fn snd2[A, B](p :: (A, B)) -> B {
  match p {
    (_, b) => b,
  }
}

# Close any dangling text/tool spans -- called on FinishDelta and StepDone
# so a run never leaves an unterminated TEXT_MESSAGE_START or
# TOOL_CALL_START dangling on the wire.
fn close_open(st :: BridgeState) -> (List[ev.AguiEvent], BridgeState) {
  let text_step := match st.in_text {
    None => (no_events(), st),
    Some(mid) => ([ev.TextMessageEnd({ message_id: mid })], with_text(st, None)),
  }
  let text_events := fst2(text_step)
  let st_after_text := snd2(text_step)
  match st_after_text.in_tool {
    None => (text_events, st_after_text),
    Some(tid) => (list.concat(text_events, [ev.ToolCallEnd({ tool_call_id: tid })]), with_tool(st_after_text, None)),
  }
}

fn text_chunk_events(text :: Str, st :: BridgeState) -> StepOutcome {
  match st.in_text {
    None => {
      let idr := fresh_id(st, "msg")
      let id := fst2(idr)
      let st1 := snd2(idr)
      { events: [ev.TextMessageStart({ message_id: id, role: "assistant" }), ev.TextMessageContent({ message_id: id, delta: text })], st: with_text(st1, Some(id)), is_final: false }
    },
    Some(id) => { events: [ev.TextMessageContent({ message_id: id, delta: text })], st: st, is_final: false },
  }
}

fn tool_call_begin_events(id :: Str, name :: Str, st :: BridgeState) -> StepOutcome {
  let closed := match st.in_text {
    None => no_events(),
    Some(mid) => [ev.TextMessageEnd({ message_id: mid })],
  }
  let st1 := with_tool(with_text(st, None), Some(id))
  { events: list.concat(closed, [ev.ToolCallStart({ tool_call_id: id, tool_call_name: name, parent_message_id: None })]), st: st1, is_final: false }
}

fn finish_delta_events(st :: BridgeState) -> StepOutcome {
  let r := close_open(st)
  { events: fst2(r), st: snd2(r), is_final: false }
}

fn tool_exec_events(id :: Str, st :: BridgeState) -> StepOutcome {
  { events: [ev.ToolCallEnd({ tool_call_id: id })], st: with_tool(st, None), is_final: false }
}

fn tool_result_events(id :: Str, success :: Bool, st :: BridgeState) -> StepOutcome {
  let content := if success {
    "ok"
  } else {
    "error"
  }
  let idr := fresh_id(st, "toolresult")
  let mid := fst2(idr)
  let st1 := snd2(idr)
  { events: [ev.ToolCallResult({ message_id: mid, tool_call_id: id, content: content })], st: st1, is_final: false }
}

fn step_done_events(st :: BridgeState) -> StepOutcome {
  let r := close_open(st)
  { events: fst2(r), st: snd2(r), is_final: true }
}

fn delta_events(delta :: d.Delta, st :: BridgeState) -> StepOutcome {
  match delta {
    TextChunk(text) => text_chunk_events(text, st),
    ToolCallBegin(id, name) => tool_call_begin_events(id, name, st),
    ToolArgChunk(id, chunk) => { events: [ev.ToolCallArgs({ tool_call_id: id, delta: chunk })], st: st, is_final: false },
    FinishDelta(_) => finish_delta_events(st),
    UsageDelta(_) => { events: no_events(), st: st, is_final: false },
  }
}

# Expand one lex-llm Step into zero or more AG-UI events, returning the
# updated state and whether this step ends the run.
fn step_events(step :: d.Step, st :: BridgeState) -> StepOutcome {
  match step {
    StepDelta(delta) => delta_events(delta, st),
    StepToolExec(_, id) => tool_exec_events(id, st),
    StepToolResult(id, success) => tool_result_events(id, success, st),
    StepDone(_) => step_done_events(st),
  }
}

fn fold_step(acc :: FoldAcc, step :: d.Step) -> FoldAcc {
  if acc.done {
    acc
  } else {
    let outcome := step_events(step, acc.st)
    { events: list.concat(acc.events, outcome.events), st: outcome.st, done: outcome.is_final }
  }
}

# Public entry point: turn a lex-llm step stream into the AG-UI event
# list, opening with RUN_STARTED and always closing with RUN_FINISHED
# (even if the input stream ends without a StepDone -- defensive, so a
# consumer's SSE connection never hangs waiting for a terminator).
fn from_llm_steps(steps :: Iter[d.Step], thread_id :: Str, run_id :: Str) -> Iter[ev.AguiEvent] {
  let st0 := { in_text: None, in_tool: None, thread_id: thread_id, run_id: run_id, counter: 0 }
  let step_list := iter.to_list(steps)
  let acc0 := { events: no_events(), st: st0, done: false }
  let folded := list.fold(step_list, acc0, fold_step)
  let closing := list.concat(folded.events, [run_finished_event(folded.st)])
  let all_events := list.concat([ev.RunStarted({ thread_id: thread_id, run_id: run_id })], closing)
  iter.from_list(all_events)
}

