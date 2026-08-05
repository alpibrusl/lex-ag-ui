# lex-ag-ui — bridge ANY A2A agent's tasks/sendSubscribe stream into
# AG-UI events. No changes to lex-agent, lex-soft, or any individual
# pack needed -- `lex-agent/src/mount.lex` already auto-detects
# `tasks/sendSubscribe` in the request body and serves it as SSE for
# every `AgentDef`-mounted agent (confirmed: lex-agent/src/server.lex's
# `dispatch_subscribe_str`/`build_subscribe_frames`, wired
# automatically by mount.lex). This module is a pure client-side
# translator sitting on top of `lex-agent/src/client.lex`'s existing
# `subscribe` function, which already decodes that SSE stream into
# typed `List[tk.StatusUpdate]`.
#
# Practical effect: every lex-soft pack persona (custody, coldchain,
# tradefinance's siblings, etc. -- anything built as a `pack.DomainPack`
# via `Persona.build: (Db, Str) -> lex-agent.AgentDef`) and every other
# lex-agent-based server (including lex-oms-agent's own A2A endpoint)
# gets AG-UI streaming for free through this one bridge, with zero
# per-agent code. Point it at any agent's base URL.
#
# Coarser than lex-oms-agent's own agui_adapter.lex, by design: A2A's
# StatusUpdate only carries task-lifecycle transitions (submitted ->
# working -> completed/failed) plus an optional message, not
# tool-call-level detail (that needs an agent-specific adapter, same as
# lex-oms-agent's, because tool calls are business logic the A2A
# protocol itself has no vocabulary for). Use this bridge as the
# zero-effort default for any A2A agent; write a bespoke adapter (like
# lex-oms-agent's) only when you need richer visibility than
# task-lifecycle events give you.
#
# Effects: from_status_updates is pure. subscribe_as_agui carries
# lex-agent/src/client.lex's `subscribe`'s own effect row
# ([net, crypto, random, stream]) -- it does one real network call.

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "lex-agent/src/client" as a2a_client

import "lex-agent/src/task" as tk

import "lex-agent/src/message" as msg

import "./event" as ev

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

fn no_events() -> List[ev.AguiEvent] {
  []
}

fn first_text(parts :: List[msg.Part]) -> Option[Str] {
  match list.head(parts) {
    Some(TextPart(s)) => Some(s),
    _ => None,
  }
}

fn message_events(m :: msg.Message, counter :: Int) -> (List[ev.AguiEvent], Int) {
  match first_text(m.parts) {
    None => ([], counter),
    Some(text) => {
      let id := str.concat("msg_", int.to_str(counter))
      ([ev.TextMessageStart({ message_id: id, role: "assistant" }), ev.TextMessageContent({ message_id: id, delta: text }), ev.TextMessageEnd({ message_id: id })], counter + 1)
    },
  }
}

type FoldAcc = { events :: List[ev.AguiEvent], counter :: Int, final_state :: Option[tk.TaskState] }

fn fold_update(acc :: FoldAcc, u :: tk.StatusUpdate) -> FoldAcc {
  let part := match u.message {
    None => (no_events(), acc.counter),
    Some(m) => message_events(m, acc.counter),
  }
  let evs := fst2(part)
  let counter2 := snd2(part)
  let final_state := if u.final {
    Some(u.state)
  } else {
    acc.final_state
  }
  { events: list.concat(acc.events, evs), counter: counter2, final_state: final_state }
}

fn closing_events(final_state :: Option[tk.TaskState], thread_id :: Str, run_id :: Str) -> List[ev.AguiEvent] {
  match final_state {
    Some(TSFailed) => [ev.RunError({ message: "A2A task failed", code: None })],
    Some(TSCanceled) => [ev.RunError({ message: "A2A task canceled", code: None })],
    _ => [ev.RunFinished({ thread_id: thread_id, run_id: run_id })],
  }
}

# Public entry point: a completed sendSubscribe response (already
# decoded to List[StatusUpdate] by lex-agent/src/client.lex's
# `subscribe`) -> the full AG-UI event list for that run.
fn from_status_updates(updates :: List[tk.StatusUpdate], thread_id :: Str, run_id :: Str) -> List[ev.AguiEvent] {
  let acc0 := { events: no_events(), counter: 0, final_state: None }
  let folded := list.fold(updates, acc0, fold_update)
  list.concat([ev.RunStarted({ thread_id: thread_id, run_id: run_id })], list.concat(folded.events, closing_events(folded.final_state, thread_id, run_id)))
}

# Call any A2A agent's tasks/sendSubscribe and bridge the result to
# AG-UI events in one step.
fn subscribe_as_agui(peer_url :: Str, m :: msg.Message, opts :: a2a_client.SendOpts, api_key :: Str, thread_id :: Str, run_id :: Str) -> [net, crypto, random, stream] Result[List[ev.AguiEvent], Str] {
  match a2a_client.subscribe(peer_url, m, opts, api_key) {
    Err(e) => Err(e),
    Ok(updates) => Ok(from_status_updates(updates, thread_id, run_id)),
  }
}

