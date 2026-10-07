defmodule ElixirHarness.Trace do
  @moduledoc """
  One loop turn, fully traced. No instrumentation was added for this —
  `:dbg` sees every call because the VM already does.
  """

  @traced [
    {ElixirHarness.Session, [:append, :history, :to_prompt]},
    {ElixirHarness.ToolRunner, [:run]},
    {ElixirHarness.Toon, [:encode!, :decode]},
    {ElixirHarness.Loop, [:run]}
  ]

  @doc "Trace `fun` and return `{result, calls}` where calls are `{module, fun, arity}`."
  @spec trace((-> term())) :: {term(), [{module(), atom(), arity()}]}
  def trace(fun) do
    me = self()
    forwarder = fn msg, _ -> send(me, msg) end
    {:ok, _} = :dbg.tracer(:process, {forwarder, nil})
    {:ok, _} = :dbg.p(:all, :c)

    for {mod, funs} <- @traced, f <- funs do
      {:ok, _} = :dbg.tp(mod, f, [{:_, [], [{:return_trace}]}])
    end

    result = fun.()
    calls = collect([])
    :dbg.stop()
    {result, calls}
  end

  defp collect(acc) do
    receive do
      {:trace, _pid, :call, {m, f, args}} when is_list(args) ->
        collect([{m, f, length(args)} | acc])

      {:trace, _pid, :return_from, _} ->
        collect(acc)
    after
      200 -> Enum.reverse(acc)
    end
  end

  @doc "Human-readable summary of a traced turn."
  @spec summarize([{module(), atom(), arity()}]) :: [String.t()]
  def summarize(calls) do
    calls
    |> Enum.map(fn {m, f, a} -> "#{short(m)}.#{f}/#{a}" end)
    |> Enum.uniq()
  end

  defp short(mod), do: mod |> Module.split() |> List.last()
end

defmodule Mix.Tasks.Demo.Trace do
  @shortdoc "Trace one agent loop turn with :dbg"
  use Mix.Task

  @impl true
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)

    scripted = fn ->
      {:ok, s} = ElixirHarness.Session.start_link()
      :ok = ElixirHarness.Session.append(s, "user", "add 1 and 2")

      ElixirHarness.Loop.run(s, ElixirHarness.Trace.MockAdapter, [ElixirHarness.Tools.Math],
        adapter_opts: [calls: self()]
      )
    end

    {{:ok, final}, calls} = ElixirHarness.Trace.trace(scripted)

    IO.puts("final: #{final}")
    IO.puts("calls observed:")

    for line <- ElixirHarness.Trace.summarize(calls) do
      IO.puts("  #{line}")
    end
  end
end

defmodule ElixirHarness.Trace.MockAdapter do
  @moduledoc false
  @behaviour ElixirHarness.CLIAdapter

  @impl true
  def run(_prompt, opts) do
    caller = Keyword.fetch!(opts, :calls)
    send(caller, {:trace_probe, :adapter_called})
    {:ok, ElixirHarness.Toon.encode!(%{"action" => "final", "content" => "traced"})}
  end
end
