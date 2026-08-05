# lex-ag-ui — carry an A2UI message over an AG-UI stream.
#
# The documented composition of these two protocols: A2UI is a
# declarative UI payload format; AG-UI is the agent<->frontend event
# transport. A2UI messages ride inside AG-UI's CUSTOM event, keyed
# "a2ui" -- an AG-UI-aware client that doesn't understand A2UI still
# gets a well-formed event stream (it just won't render the custom
# payload); an A2UI-aware renderer looks for CUSTOM events named "a2ui"
# and decodes the value as an A2UI envelope.
#
# Effects: none. Construction is pure.

import "lex-a2ui/src/message" as a2ui

import "./event" as ev

fn custom_event(msg :: a2ui.A2uiMessage) -> ev.AguiEvent {
  CustomEvt({ name: "a2ui", value: a2ui.to_json(msg) })
}

