# lex-ag-ui — one-call integration: mount a streaming AG-UI endpoint.
#
# This is the actual "easily integrate AG-UI into any agentic Lex
# service" entry point. Two layers, narrow to wide:
#
#   add_to_events -- the TRUE generic primitive. Needs only a function
#   producing `Iter[ev.AguiEvent]` -- no dependency on lex-llm's Step
#   type, lex-agent's AgentDef, or anything else. Any agent whose
#   internal step/decision representation ISN'T lex-llm's Delta stream
#   (e.g. lex-oms-agent's own tool-call history type) still integrates
#   with one small adapter function converting its own steps to
#   AguiEvent, then this.
#
#   add_to -- the convenience wrapper for the common case: an agent
#   built directly on `lex-llm/src/agent.lex`'s `run_loop`, which
#   already returns `Iter[d.Step]`.
#
# Usage (common case, lex-llm-backed):
#
#   import "lex-ag-ui/src/mount" as agui_mount
#   import "lex-llm/src/agent" as llm_agent
#
#   let r := agui_mount.add_to(router.new(), "/agui/:thread_id", fn (c :: ctx.Ctx) -> [...] Iter[d.Step] {
#     llm_agent.run_loop(my_agent, conversation_from_request(c))
#   })
#
# Usage (custom step type, e.g. lex-oms-agent's tool-call history):
#
#   let r := agui_mount.add_to_events(router.new(), "/agui/:thread_id", fn (c :: ctx.Ctx) -> [...] Iter[ev.AguiEvent] {
#     my_own_adapter(my_agent_run(c))  -- my_own_adapter: MyStep -> AguiEvent
#   })

import "std.map" as map

import "std.crypto" as crypto

import "lex-web/src/router" as router

import "lex-web/src/ctx" as ctx

import "lex-web/src/stream" as stream

import "lex-llm/src/delta" as d

import "./event" as ev

import "./bridge" as bridge

import "./sse" as sse

# thread_id: if `path` captures a `:thread_id` segment (e.g.
# "/agui/:thread_id"), it's read from there, so a frontend can reuse one
# AG-UI thread across multiple requests/turns. Otherwise a fresh one is
# minted per call.
fn resolve_thread_id(c :: ctx.Ctx) -> [random] Str {
  match map.get(c.path_params, "thread_id") {
    Some(t) => t,
    None => crypto.random_str_hex(8),
  }
}

# The generic primitive -- see module doc. `run` produces the reply's
# AG-UI event stream directly; how it gets there is entirely the
# caller's business.
fn add_to_events(r :: router.Router, path :: Str, run :: (ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Iter[ev.AguiEvent]) -> router.Router {
  router.route_stream(r, "POST", path, fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] stream.StreamResponse {
    sse.to_sse(run(c))
  })
}

# Convenience wrapper for the common case: an agent built on
# `lex-llm/src/agent.lex`'s `run_loop`, which already returns
# `Iter[d.Step]`. run_id is always fresh per request -- an AG-UI "run"
# is one request/response cycle by definition.
fn add_to(r :: router.Router, path :: Str, run :: (ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Iter[d.Step]) -> router.Router {
  add_to_events(r, path, fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Iter[ev.AguiEvent] {
    let thread_id := resolve_thread_id(c)
    let run_id := crypto.random_str_hex(8)
    bridge.from_llm_steps(run(c), thread_id, run_id)
  })
}

