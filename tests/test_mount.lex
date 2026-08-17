# lex-ag-ui — mount.lex test
#
# `add_to` is entirely effectful (crypto.random_str_hex needs [random],
# router dispatch needs the full HEff row) so there's no pure suite here
# -- run_all is a no-op to satisfy `lex test`'s convention. The real
# check is integration_main, run manually:
#   lex run --allow-effects io,time,crypto,random,sql,fs_read,fs_write,net,concurrent,llm,proc \
#           tests/test_mount.lex integration_main

import "std.list" as list

import "std.iter" as iter

import "std.map" as map

import "std.str" as str

import "std.int" as int

import "std.io" as io

import "lex-web/src/router" as router

import "lex-web/src/ctx" as ctx

import "lex-llm/src/delta" as d

import "../src/mount" as mount

fn check(name :: Str, cond :: Bool) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(name)
  }
}

fn run_all() -> Int {
  0
}

fn fake_run(_c :: ctx.Ctx) -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc, approval] Iter[d.Step] {
  iter.from_list([StepDelta(TextChunk("hi")), StepDone(AssistantMsg("hi", []))])
}

fn app() -> router.Router {
  mount.add_to(router.new(), "/agui/:thread_id", fake_run)
}

fn fake_request() -> ctx.RawRequest {
  { body: "", method: "POST", path: "/agui/th_1", query: "", headers: map.new() }
}

fn intg_mount_streams_agui() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc, approval] Result[Unit, Str] {
  match router.dispatch_outcome(app(), fake_request()) {
    DPlain(r) => Err(str.concat("expected a streaming response, got a plain one (status ", str.concat(int.to_str(r.status), ")"))),
    DStream(s) => match check("status 200", s.status == 200) {
      Err(msg) => Err(msg),
      Ok(_) => {
        let frames := iter.to_list(s.body)
        let joined := str.join(frames, "")
        check("SSE body carries the encoded AG-UI events", str.contains(joined, "RUN_STARTED") and str.contains(joined, "TEXT_MESSAGE_CONTENT") and str.contains(joined, "RUN_FINISHED"))
      },
    },
  }
}

fn integration_main() -> [io, time, crypto, random, sql, fs_read, fs_write, net, concurrent, llm, proc, approval] Int {
  match intg_mount_streams_agui() {
    Ok(_) => {
      let __lex_discard := io.print("ok  intg_mount_streams_agui")
      0
    },
    Err(msg) => {
      let __lex_discard := io.print(str.concat("FAIL  intg_mount_streams_agui: ", msg))
      1
    },
  }
}

