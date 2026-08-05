# lex-ag-ui — AG-UI (Agent-User Interaction Protocol) event types.
#
# Core event set only: lifecycle (RUN_*), text-message streaming
# (TEXT_MESSAGE_*), tool-call streaming (TOOL_CALL_*), and state sync
# (STATE_*). The wider AG-UI spec also has Reasoning/Activity/Thinking
# event families -- not modeled here, because lex-llm's Step/Delta
# stream (see bridge.lex) has no signal for them yet.
#
# Field names verified against the AG-UI Go SDK reference docs
# (pkg.go.dev/github.com/ag-ui-protocol/ag-ui/.../core/events, checked
# 2026-08) cross-checked against a second independent source. This was
# NOT a byte-for-byte diff of @ag-ui/core's TypeScript source -- re-verify
# against that before wiring a production frontend client.
#
# Effects: none. Construction and serialization are pure.

import "std.str" as str

import "std.int" as int

import "std.float" as float

import "std.list" as list

import "lex-schema/json_value" as jv

# ---- Event ADT -----------------------------------------------------
type AguiEvent = RunStarted({ thread_id :: Str, run_id :: Str }) | RunFinished({ thread_id :: Str, run_id :: Str }) | RunError({ message :: Str, code :: Option[Str] }) | TextMessageStart({ message_id :: Str, role :: Str }) | TextMessageContent({ message_id :: Str, delta :: Str }) | TextMessageEnd({ message_id :: Str }) | ToolCallStart({ tool_call_id :: Str, tool_call_name :: Str, parent_message_id :: Option[Str] }) | ToolCallArgs({ tool_call_id :: Str, delta :: Str }) | ToolCallEnd({ tool_call_id :: Str }) | ToolCallResult({ message_id :: Str, tool_call_id :: Str, content :: Str }) | StateSnapshot({ snapshot :: jv.Json }) | StateDelta({ delta :: jv.Json }) | CustomEvt({ name :: Str, value :: jv.Json }) | RawEvt({ event :: jv.Json })

fn jstr_opt(o :: Option[Str]) -> jv.Json {
  match o {
    None => JNull,
    Some(s) => JStr(s),
  }
}

# ---- ADT -> Json -----------------------------------------------------
fn to_json(e :: AguiEvent) -> jv.Json {
  match e {
    RunStarted(f) => JObj([("type", JStr("RUN_STARTED")), ("threadId", JStr(f.thread_id)), ("runId", JStr(f.run_id))]),
    RunFinished(f) => JObj([("type", JStr("RUN_FINISHED")), ("threadId", JStr(f.thread_id)), ("runId", JStr(f.run_id))]),
    RunError(f) => JObj([("type", JStr("RUN_ERROR")), ("message", JStr(f.message)), ("code", jstr_opt(f.code))]),
    TextMessageStart(f) => JObj([("type", JStr("TEXT_MESSAGE_START")), ("messageId", JStr(f.message_id)), ("role", JStr(f.role))]),
    TextMessageContent(f) => JObj([("type", JStr("TEXT_MESSAGE_CONTENT")), ("messageId", JStr(f.message_id)), ("delta", JStr(f.delta))]),
    TextMessageEnd(f) => JObj([("type", JStr("TEXT_MESSAGE_END")), ("messageId", JStr(f.message_id))]),
    ToolCallStart(f) => JObj([("type", JStr("TOOL_CALL_START")), ("toolCallId", JStr(f.tool_call_id)), ("toolCallName", JStr(f.tool_call_name)), ("parentMessageId", jstr_opt(f.parent_message_id))]),
    ToolCallArgs(f) => JObj([("type", JStr("TOOL_CALL_ARGS")), ("toolCallId", JStr(f.tool_call_id)), ("delta", JStr(f.delta))]),
    ToolCallEnd(f) => JObj([("type", JStr("TOOL_CALL_END")), ("toolCallId", JStr(f.tool_call_id))]),
    ToolCallResult(f) => JObj([("type", JStr("TOOL_CALL_RESULT")), ("messageId", JStr(f.message_id)), ("toolCallId", JStr(f.tool_call_id)), ("content", JStr(f.content))]),
    StateSnapshot(f) => JObj([("type", JStr("STATE_SNAPSHOT")), ("snapshot", f.snapshot)]),
    StateDelta(f) => JObj([("type", JStr("STATE_DELTA")), ("delta", f.delta)]),
    CustomEvt(f) => JObj([("type", JStr("CUSTOM")), ("name", JStr(f.name)), ("value", f.value)]),
    RawEvt(f) => JObj([("type", JStr("RAW")), ("event", f.event)]),
  }
}

# ---- Json -> Str (lex-schema/json_value has no stringify -- see README) --
fn escape_char(c :: Str) -> Str {
  match c {
    "\"" => "\\\"",
    "\\" => "\\\\",
    "\n" => "\\n",
    "\r" => "\\r",
    "\t" => "\\t",
    _ => c,
  }
}

fn escape_str(s :: Str) -> Str {
  str.join(list.map(str.split(s, ""), escape_char), "")
}

fn write_json(j :: jv.Json) -> Str {
  match j {
    JNull => "null",
    JBool(b) => if b {
      "true"
    } else {
      "false"
    },
    JInt(n) => int.to_str(n),
    JFloat(x) => float.to_str(x),
    JStr(s) => str.concat("\"", str.concat(escape_str(s), "\"")),
    JList(xs) => str.concat("[", str.concat(str.join(list.map(xs, write_json), ","), "]")),
    JObj(kvs) => str.concat("{", str.concat(str.join(list.map(kvs, write_pair), ","), "}")),
  }
}

fn write_pair(kv :: (Str, jv.Json)) -> Str {
  match kv {
    (k, v) => str.concat("\"", str.concat(escape_str(k), str.concat("\":", write_json(v)))),
  }
}

# ---- Public entry point -----------------------------------------------
fn encode(e :: AguiEvent) -> Str {
  write_json(to_json(e))
}

