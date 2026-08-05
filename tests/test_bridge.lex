# lex-ag-ui — bridge.lex tests (pure, run via `lex test`)
#
# Feeds a fake lex-llm Iter[Step] through `from_llm_steps` and asserts
# the exact AG-UI event sequence, encoded to its wire JSON so a
# mismatch is readable directly in the failure message.

import "std.list" as list

import "std.iter" as iter

import "lex-llm/src/delta" as d

import "../src/event" as ev

import "../src/bridge" as bridge

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn count_failures(results :: List[Result[Unit, Str]]) -> Int {
  list.fold(results, 0, fn (acc :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => acc,
      Err(_) => acc + 1,
    }
  })
}

fn encoded(events :: List[ev.AguiEvent]) -> List[Str] {
  list.map(events, ev.encode)
}

# ---- Text-only run: TextChunk -> FinishDelta -> StepDone -----------
fn test_text_only_run() -> Result[Unit, Str] {
  let steps := iter.from_list([StepDelta(TextChunk("Hello")), StepDelta(FinishDelta("stop")), StepDone(AssistantMsg("Hello", []))])
  let events := iter.to_list(bridge.from_llm_steps(steps, "t1", "r1"))
  let got := encoded(events)
  let want := ["{\"type\":\"RUN_STARTED\",\"threadId\":\"t1\",\"runId\":\"r1\"}", "{\"type\":\"TEXT_MESSAGE_START\",\"messageId\":\"msg_0\",\"role\":\"assistant\"}", "{\"type\":\"TEXT_MESSAGE_CONTENT\",\"messageId\":\"msg_0\",\"delta\":\"Hello\"}", "{\"type\":\"TEXT_MESSAGE_END\",\"messageId\":\"msg_0\"}", "{\"type\":\"RUN_FINISHED\",\"threadId\":\"t1\",\"runId\":\"r1\"}"]
  check("text-only run produces RUN_STARTED..TEXT_MESSAGE_*..RUN_FINISHED", got == want)
}

# ---- Tool-call run: ToolCallBegin -> ToolArgChunk -> StepToolExec -> StepToolResult -> StepDone
fn test_tool_call_run() -> Result[Unit, Str] {
  let steps := iter.from_list([StepDelta(ToolCallBegin("call_1", "get_positions")), StepDelta(ToolArgChunk("call_1", "{}")), StepToolExec("get_positions", "call_1"), StepToolResult("call_1", true), StepDone(AssistantMsg("done", []))])
  let events := iter.to_list(bridge.from_llm_steps(steps, "t1", "r1"))
  let got := encoded(events)
  let want := ["{\"type\":\"RUN_STARTED\",\"threadId\":\"t1\",\"runId\":\"r1\"}", "{\"type\":\"TOOL_CALL_START\",\"toolCallId\":\"call_1\",\"toolCallName\":\"get_positions\",\"parentMessageId\":null}", "{\"type\":\"TOOL_CALL_ARGS\",\"toolCallId\":\"call_1\",\"delta\":\"{}\"}", "{\"type\":\"TOOL_CALL_END\",\"toolCallId\":\"call_1\"}", "{\"type\":\"TOOL_CALL_RESULT\",\"messageId\":\"toolresult_0\",\"toolCallId\":\"call_1\",\"content\":\"ok\"}", "{\"type\":\"RUN_FINISHED\",\"threadId\":\"t1\",\"runId\":\"r1\"}"]
  check("tool-call run produces RUN_STARTED..TOOL_CALL_*..RUN_FINISHED", got == want)
}

# ---- Defensive terminator: a stream with no StepDone still closes --
fn test_no_stepdone_still_finishes() -> Result[Unit, Str] {
  let steps := iter.from_list([StepDelta(TextChunk("hi"))])
  let events := iter.to_list(bridge.from_llm_steps(steps, "t1", "r1"))
  let got := encoded(events)
  let want := ["{\"type\":\"RUN_STARTED\",\"threadId\":\"t1\",\"runId\":\"r1\"}", "{\"type\":\"TEXT_MESSAGE_START\",\"messageId\":\"msg_0\",\"role\":\"assistant\"}", "{\"type\":\"TEXT_MESSAGE_CONTENT\",\"messageId\":\"msg_0\",\"delta\":\"hi\"}", "{\"type\":\"RUN_FINISHED\",\"threadId\":\"t1\",\"runId\":\"r1\"}"]
  check("stream without StepDone still emits RUN_FINISHED (no TEXT_MESSAGE_END -- input never closed it)", got == want)
}

fn suite_pure() -> List[Result[Unit, Str]] {
  [test_text_only_run(), test_tool_call_run(), test_no_stepdone_still_finishes()]
}

fn run_all() -> Int {
  count_failures(suite_pure())
}

