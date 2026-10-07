# ElixirHarness

Elixir as an agent harness language, using OTP built-ins instead of
frameworks: `GenServer` sessions, `Task.Supervisor` tool isolation,
`DynamicSupervisor` + `Registry` + `:pg` orchestration, ETS/Mnesia memory,
`Port` subprocess adapters — with TOON (`toon_ex`) as the token-efficient
wire format to OpenCode / Cursor CLIs.

## Layout

- `lib/elixir_harness/` — minimal library (`Tool`, `ToolRunner`, `Session`,
  `Memory`, `Toon`, `CLI`, `Loop`, `Orchestrator`, `Cluster`)
- `lib/mix/tasks/demo.ex` — headless demos (`mix demo.crash`, `demo.parallel`,
  `demo.cli`, `demo.memory`, `demo.toon_stats`)
- `notebooks/*.livemd` — one Livebook per use case

## Run

```sh
mix deps.get
mix test
mix demo.crash && mix demo.parallel && mix demo.toon_stats
mix showcase cluster
mix dashboard  # mission control at http://localhost:4000
```

## Showcases

One module per demoable feature under `ElixirHarness.Showcase`
(`mix showcase` lists, `mix showcase <name>` runs):

- `cluster` — two-node fan-out surviving `kill -9`
- `dashboard` — LiveView mission control with live traffic
- `calc` — safe formula evaluation vs hostile input
- `upgrade` — hot code upgrade mid-session
