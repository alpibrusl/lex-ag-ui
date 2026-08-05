# lex-ag-ui — event.lex tests (pure, run via `lex test`)

import "std.list" as list

import "../src/event" as ev

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

fn test_run_started() -> Result[Unit, Str] {
  let got := ev.encode(RunStarted({ thread_id: "t1", run_id: "r1" }))
  check("RUN_STARTED wire shape", got == "{\"type\":\"RUN_STARTED\",\"threadId\":\"t1\",\"runId\":\"r1\"}")
}

fn test_run_finished() -> Result[Unit, Str] {
  let got := ev.encode(RunFinished({ thread_id: "t1", run_id: "r1" }))
  check("RUN_FINISHED wire shape", got == "{\"type\":\"RUN_FINISHED\",\"threadId\":\"t1\",\"runId\":\"r1\"}")
}

fn test_run_error_no_code() -> Result[Unit, Str] {
  let got := ev.encode(RunError({ message: "boom", code: None }))
  check("RUN_ERROR null code", got == "{\"type\":\"RUN_ERROR\",\"message\":\"boom\",\"code\":null}")
}

fn test_text_message_content_escapes() -> Result[Unit, Str] {
  let got := ev.encode(TextMessageContent({ message_id: "msg_0", delta: "say \"hi\"\nnext line" }))
  check("TEXT_MESSAGE_CONTENT escapes quotes/newlines", got == "{\"type\":\"TEXT_MESSAGE_CONTENT\",\"messageId\":\"msg_0\",\"delta\":\"say \\\"hi\\\"\\nnext line\"}")
}

fn test_tool_call_start_no_parent() -> Result[Unit, Str] {
  let got := ev.encode(ToolCallStart({ tool_call_id: "call_1", tool_call_name: "get_positions", parent_message_id: None }))
  check("TOOL_CALL_START null parentMessageId", got == "{\"type\":\"TOOL_CALL_START\",\"toolCallId\":\"call_1\",\"toolCallName\":\"get_positions\",\"parentMessageId\":null}")
}

fn test_tool_call_result() -> Result[Unit, Str] {
  let got := ev.encode(ToolCallResult({ message_id: "toolresult_0", tool_call_id: "call_1", content: "ok" }))
  check("TOOL_CALL_RESULT wire shape", got == "{\"type\":\"TOOL_CALL_RESULT\",\"messageId\":\"toolresult_0\",\"toolCallId\":\"call_1\",\"content\":\"ok\"}")
}

fn suite_pure() -> List[Result[Unit, Str]] {
  [test_run_started(), test_run_finished(), test_run_error_no_code(), test_text_message_content_escapes(), test_tool_call_start_no_parent(), test_tool_call_result()]
}

# See tests/test_bridge.lex's comment: `lex test` discards run_all's
# return value and only checks for a runtime error, so a plain
# count_failures(...) return never actually gates CI. Force a real
# runtime error (integer division by zero) when there are failures.
fn run_all() -> Int {
  let failures := count_failures(suite_pure())
  let _crash_if_failed := if failures > 0 {
    1 / 0
  } else {
    0
  }
  failures
}

