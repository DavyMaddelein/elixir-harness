defmodule ElixirHarness.Showcase.Trace do
  @moduledoc "Showcase: one loop turn, every call observed."
  @behaviour ElixirHarness.Showcase

  @impl true
  def name, do: "trace"

  @impl true
  def description, do: "Trace one agent loop turn with :dbg — zero instrumentation added."

  @impl true
  def run do
    scripted = fn ->
      {:ok, s} = ElixirHarness.Session.start_link()
      :ok = ElixirHarness.Session.append(s, "user", "add 1 and 2")

      ElixirHarness.Loop.run(s, ElixirHarness.Trace.MockAdapter, [ElixirHarness.Tools.Math],
        adapter_opts: [calls: self()]
      )
    end

    {{:ok, final}, calls} = ElixirHarness.Trace.trace(scripted)
    IO.puts("final: #{final}\ncalls observed:")

    for line <- ElixirHarness.Trace.summarize(calls) do
      IO.puts("  #{line}")
    end

    :ok
  end
end
