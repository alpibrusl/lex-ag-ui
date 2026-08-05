# lex-ag-ui — a2ui_bridge.lex tests (pure, run via `lex test`)

import "std.list" as list

import "lex-a2ui/src/message" as a2ui

import "../src/event" as ev

import "../src/a2ui_bridge" as bridge

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

fn test_a2ui_message_rides_as_custom_event() -> Result[Unit, Str] {
  let a2ui_msg := DeleteSurfaceMsg({ surface_id: "s1" })
  let agui_event := bridge.custom_event(a2ui_msg)
  let got := ev.encode(agui_event)
  let want := "{\"type\":\"CUSTOM\",\"name\":\"a2ui\",\"value\":{\"version\":\"v1.0\",\"deleteSurface\":{\"surfaceId\":\"s1\"}}}"
  check("A2UI message wire-identical whether encoded directly or unwrapped from the CUSTOM event", got == want)
}

fn test_a2ui_payload_matches_standalone_encode() -> Result[Unit, Str] {
  let a2ui_msg := UpdateDataModelMsg({ surface_id: "s1", path: Some("/x"), value: JStr("y") })
  let agui_event := bridge.custom_event(a2ui_msg)
  let got := ev.encode(agui_event)
  let standalone := a2ui.encode(a2ui_msg)
  check("the wrapped value is exactly a2ui.encode's output, just nested one level under CUSTOM.value", got == "{\"type\":\"CUSTOM\",\"name\":\"a2ui\",\"value\":" + standalone + "}")
}

fn suite_pure() -> List[Result[Unit, Str]] {
  [test_a2ui_message_rides_as_custom_event(), test_a2ui_payload_matches_standalone_encode()]
}

# lex test discards run_all's return value and only checks whether the
# call raises a runtime error -- see lex-ag-ui's README. Force a real
# runtime error when there are failures so this suite actually gates.
fn run_all() -> Int {
  let failures := count_failures(suite_pure())
  let _crash_if_failed := if failures > 0 {
    1 / 0
  } else {
    0
  }
  failures
}

