defmodule ElixirHarness.Showcase.Pg do
  @moduledoc "Showcase: observations broadcast to every agent. No Redis."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{Orchestrator, Tools.Math}

  @impl true
  def name, do: "pg"

  @impl true
  def description,
    do: "Every fan-out result goes to all :agents members. Membership is :pg, delivery is send."

  @impl true
  def run do
    :pg.join(:agents, self())
    tasks = for i <- 1..3, do: {Math, %{"op" => "add", "a" => i, "b" => 0}}
    Orchestrator.fan_out(tasks, max_concurrency: 3)

    for _ <- 1..3 do
      receive do
        {:observation, %{tool: t, result: {:ok, v}}} -> IO.puts("observed #{t} -> #{v}")
      after
        5_000 -> IO.puts("missed an observation!")
      end
    end

    :ok
  end
end
