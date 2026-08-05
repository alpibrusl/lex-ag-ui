# lex-ag-ui — one-call integration: mount a streaming AG-UI endpoint.
#
# This is the actual "easily integrate AG-UI into any agentic Lex
# service" entry point. It deliberately does NOT depend on lex-agent's
# `AgentDef`/`Skill` -- not every agent server in this ecosystem uses
# that type (lex-oms-agent's `a2a_agent.lex` hand-rolls its own routing,
# for one), and coupling to it would narrow "any agentic development" to
# "any lex-agent-shaped development." Instead `add_to` only needs a
# function that produces lex-llm's `Iter[d.Step]` -- which is what
# `lex-llm/src/agent.lex`'s `run_loop` already returns, whether or not
# the caller is built on `lex-agent`.
#
# Usage:
#
#   import "lex-ag-ui/src/mount" as agui_mount
#   import "lex-llm/src/agent" as llm_agent
#
#   let r := agui_mount.add_to(router.new(), "/agui/:thread_id", fn (c :: ctx.Ctx) -> [...] Iter[d.Step] {
#     llm_agent.run_loop(my_agent, conversation_from_request(c))
#   })
#
# That's the whole integration -- one import, one function, one route.

import "std.map" as map

import "std.crypto" as crypto

import "lex-web/src/router" as router

import "lex-web/src/ctx" as ctx

import "lex-web/src/stream" as stream

import "lex-llm/src/delta" as d

import "./bridge" as bridge

import "./sse" as sse

# Mount a streaming AG-UI endpoint at `path` (`POST`). `run` receives the
# request context and produces the reply's step stream.
#
# thread_id: if `path` captures a `:thread_id` segment (e.g.
# "/agui/:thread_id"), it's read from there, so a frontend can reuse one
# AG-UI thread across multiple requests/turns. Otherwise a fresh one is
# minted per call. run_id is always fresh per request -- an AG-UI "run"
# is one request/response cycle by definition.
fn add_to(r :: router.Router, path :: Str, run :: (ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] Iter[d.Step]) -> router.Router {
  router.route_stream(r, "POST", path, fn (c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc] stream.StreamResponse {
    let thread_id := match map.get(c.path_params, "thread_id") {
      Some(t) => t,
      None => crypto.random_str_hex(8),
    }
    let run_id := crypto.random_str_hex(8)
    let steps := run(c)
    sse.to_sse(bridge.from_llm_steps(steps, thread_id, run_id))
  })
}

