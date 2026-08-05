# lex-ag-ui — SSE transport, built on lex-web's existing streaming
# support (lex-web/src/stream.lex's `event_stream`/`StreamResponse`,
# already wired through `router.route_stream` + `dispatch_outcome`).
# No new runtime plumbing needed here -- just encoding.

import "std.iter" as iter

import "lex-web/src/stream" as stream

import "./event" as ev

# Wrap an AG-UI event stream as an SSE `StreamResponse`. Mount the
# returned value's producing function via `router.route_stream` and
# bridge through `router.dispatch_outcome` in your `main` -- see
# lex-web/examples/streaming_api.lex for the DPlain/DStream match.
fn to_sse(events :: Iter[ev.AguiEvent]) -> stream.StreamResponse {
  stream.event_stream(iter.map(events, ev.encode))
}

