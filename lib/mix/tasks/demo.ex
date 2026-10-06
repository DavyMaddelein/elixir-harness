defmodule Mix.Tasks.Demo.Crash do
  @shortdoc "Show a crashing tool cannot take down the session"
  use Mix.Task

  @impl true
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)
    {:ok, session} = ElixirHarness.Session.start_link()
    :ok = ElixirHarness.Session.append(session, "user", "divide by zero")

    defmodule Boom do
      use ElixirHarness.Tool
      tool_name("boom")
      tool_description("Raises.")
      tool_schema(%{})
      @impl true
      def run(_), do: raise("boom")
    end

    IO.inspect(ElixirHarness.ToolRunner.run(Boom, %{}), label: "crash result")

    IO.inspect(
      ElixirHarness.ToolRunner.run(ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 2}),
      label: "session survives"
    )
  end
end

defmodule Mix.Tasks.Demo.Parallel do
  @shortdoc "Benchmark sequential vs supervised fan-out"
  use Mix.Task

  @impl true
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)
    alias ElixirHarness.Tools.Math

    tasks = for i <- 1..8, do: {Math, %{"op" => "add", "a" => i, "b" => 0}}

    {seq_ms, seq} =
      :timer.tc(fn -> Enum.map(tasks, fn {t, a} -> ElixirHarness.ToolRunner.run(t, a) end) end)

    {par_ms, par} =
      :timer.tc(fn -> ElixirHarness.Orchestrator.fan_out(tasks, max_concurrency: 8) end)

    IO.puts("sequential: #{div(seq_ms, 1000)}ms, parallel: #{div(par_ms, 1000)}ms")
    IO.inspect({seq, par}, label: "results match", limit: 3)
  end
end

defmodule Mix.Tasks.Demo.Cli do
  @shortdoc "Stream a CLI subprocess with budgets"
  use Mix.Task

  @impl true
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)

    {:ok, out} =
      ElixirHarness.CLI.OpenCode.run("hello from demo",
        exe: "/bin/echo",
        args: [],
        on_line: &IO.puts("line> #{&1}")
      )

    IO.inspect(out, label: "collected")
  end
end

defmodule Mix.Tasks.Demo.Memory do
  @shortdoc "Append to a session and print its TOON prompt"
  use Mix.Task

  @impl true
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)
    {:ok, s} = ElixirHarness.Session.start_link()
    :ok = ElixirHarness.Session.append(s, "user", "deploy friday?")
    :ok = ElixirHarness.Session.append(s, "assistant", "only with a rollback plan")
    IO.puts(ElixirHarness.Session.to_prompt(s))
  end
end

defmodule Mix.Tasks.Demo.ToonStats do
  @shortdoc "Compare JSON vs TOON sizes on harness payloads"
  use Mix.Task

  @impl true
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)

    uniform = %{
      "tools" => for(i <- 1..20, do: %{"name" => "tool#{i}", "description" => "does thing #{i}"})
    }

    nested = %{
      "session" => %{"id" => "abc", "meta" => %{"deep" => %{"deeper" => [1, 2, %{"x" => 1}]}}}
    }

    IO.inspect(ElixirHarness.Toon.stats(uniform), label: "uniform (TOON wins)")
    IO.inspect(ElixirHarness.Toon.stats(nested), label: "nested (JSON may win)")
  end
end
