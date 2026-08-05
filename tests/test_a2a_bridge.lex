# lex-ag-ui — a2a_bridge.lex tests (pure, run via `lex test`)
#
# from_status_updates is the pure half (no network) -- these tests
# cover it directly. subscribe_as_agui itself is a one-line wrapper
# with a real network call, not independently tested here.

import "std.list" as list

import "lex-agent/src/message" as msg

import "../src/event" as ev

import "../src/a2a_bridge" as bridge

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

fn agent_msg(text :: Str) -> msg.Message {
  { message_id: "m1", role: RoleAgent, parts: [TextPart(text)], context_id: "ctx_1" }
}

fn test_working_then_completed_with_message() -> Result[Unit, Str] {
  let updates := [{ task_id: "t1", state: TSWorking, message: None, final: false }, { task_id: "t1", state: TSCompleted, message: Some(agent_msg("done")), final: true }]
  let got := encoded(bridge.from_status_updates(updates, "th1", "r1"))
  let want := ["{\"type\":\"RUN_STARTED\",\"threadId\":\"th1\",\"runId\":\"r1\"}", "{\"type\":\"TEXT_MESSAGE_START\",\"messageId\":\"msg_0\",\"role\":\"assistant\"}", "{\"type\":\"TEXT_MESSAGE_CONTENT\",\"messageId\":\"msg_0\",\"delta\":\"done\"}", "{\"type\":\"TEXT_MESSAGE_END\",\"messageId\":\"msg_0\"}", "{\"type\":\"RUN_FINISHED\",\"threadId\":\"th1\",\"runId\":\"r1\"}"]
  check("working (no message) then completed (with message) -> RUN_STARTED..TEXT_MESSAGE_*..RUN_FINISHED", got == want)
}

fn test_failed_emits_run_error_not_run_finished() -> Result[Unit, Str] {
  let updates := [{ task_id: "t1", state: TSFailed, message: None, final: true }]
  let got := encoded(bridge.from_status_updates(updates, "th1", "r1"))
  let want := ["{\"type\":\"RUN_STARTED\",\"threadId\":\"th1\",\"runId\":\"r1\"}", "{\"type\":\"RUN_ERROR\",\"message\":\"A2A task failed\",\"code\":null}"]
  check("TSFailed -> RUN_ERROR, not RUN_FINISHED", got == want)
}

fn test_no_updates_still_wraps_run_started_finished() -> Result[Unit, Str] {
  let got := encoded(bridge.from_status_updates([], "th1", "r1"))
  let want := ["{\"type\":\"RUN_STARTED\",\"threadId\":\"th1\",\"runId\":\"r1\"}", "{\"type\":\"RUN_FINISHED\",\"threadId\":\"th1\",\"runId\":\"r1\"}"]
  check("empty update list still produces a well-formed RUN_STARTED/RUN_FINISHED pair", got == want)
}

fn suite_pure() -> List[Result[Unit, Str]] {
  [test_working_then_completed_with_message(), test_failed_emits_run_error_not_run_finished(), test_no_updates_still_wraps_run_started_finished()]
}

# lex test discards run_all's return value and only checks whether the
# call raises a runtime error -- see lex-ag-ui's README. Force a real
# runtime error when there are failures.
fn run_all() -> Int {
  let failures := count_failures(suite_pure())
  let _crash_if_failed := if failures > 0 {
    1 / 0
  } else {
    0
  }
  failures
}

