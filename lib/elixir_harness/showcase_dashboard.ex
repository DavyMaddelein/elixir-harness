defmodule Mix.Tasks.Dashboard do
  @shortdoc "Boot mission control on http://localhost:4000"
  use Mix.Task

  @impl true
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)
    port = args |> List.first("4000") |> String.to_integer()
    {:ok, _} = ElixirHarness.Dashboard.boot(port)
    Mix.shell().info("mission control at http://localhost:#{port} (Ctrl-C to stop)")
    Process.sleep(:infinity)
  end
end

defmodule ElixirHarness.Showcase.Dashboard do
  @moduledoc "Showcase: mission control with live traffic."
  @behaviour ElixirHarness.Showcase

  @impl true
  def name, do: "dashboard"

  @impl true
  def description,
    do: "LiveView mission control: supervision tree, workers, live tool log, TOON viewer."

  @impl true
  def run do
    {:ok, _} = ElixirHarness.Dashboard.boot(4000)
    IO.puts("mission control at http://localhost:4000 — open it, then press Ctrl-C here")
    tasks = for i <- 1..6, do: {ElixirHarness.Tools.Math, %{"op" => "add", "a" => i, "b" => 0}}
    ElixirHarness.Orchestrator.fan_out(tasks, max_concurrency: 6)
    IO.puts("demo traffic generated — watch the tool log update live")
    Process.sleep(:infinity)
  end
end
