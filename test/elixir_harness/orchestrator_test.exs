defmodule ElixirHarness.OrchestratorTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.{Orchestrator, AgentWorker}
  alias ElixirHarness.Tools.Math

  defmodule Boom do
    use ElixirHarness.Tool
    tool_name("boom")
    tool_description("Always raises.")
    tool_schema(%{})
    @impl true
    def run(_), do: raise("worker boom")
  end

  test "registry resolves workers and :pg tracks them" do
    {:ok, _} = Orchestrator.start_worker("w1")
    assert [{pid, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "w1")
    assert is_pid(pid)
    assert pid in Orchestrator.members()

    assert {:ok, _} =
             AgentWorker.run_task(pid, {:tool, Math, %{"op" => "add", "a" => 1, "b" => 2}})
  end

  test "fan_out completes batch despite a crasher" do
    tasks =
      for i <- 1..9 do
        {Math, %{"op" => "add", "a" => i, "b" => 0}}
      end ++ [{Boom, %{}}]

    results = Orchestrator.fan_out(tasks, max_concurrency: 4, timeout: 10_000)
    assert length(results) == 10
    assert Enum.count(results, &match?({:ok, _}, &1)) == 9
    assert Enum.any?(results, &match?({:error, _}, &1))
  end

  test "cluster rpc runs locally on self node" do
    assert 3 = ElixirHarness.Cluster.rpc(Node.self(), Kernel, :+, [1, 2])
  end
end
