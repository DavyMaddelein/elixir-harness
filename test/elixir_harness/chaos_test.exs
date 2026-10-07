defmodule ElixirHarness.ChaosTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.{Chaos, Restarter, Orchestrator, AgentWorker}

  test "rest_for_one restarts b and c, never a" do
    {:ok, sup} = Restarter.start_link()
    [a, b, c] = Restarter.pids(sup)
    Process.exit(b, :kill)
    Process.sleep(300)
    [a2, b2, c2] = Restarter.pids(sup)
    assert a == a2
    assert b != b2
    assert c != c2
  end

  test "permanent worker recovers under the same name" do
    {:ok, _} = Orchestrator.start_worker("chaos-t1", restart: :permanent)
    [{pid, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "chaos-t1")
    Process.exit(pid, :kill)
    Process.sleep(500)
    [{pid2, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "chaos-t1")
    assert pid != pid2

    assert {:ok, 3} =
             AgentWorker.run_task(
               pid2,
               {:tool, ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 2}}
             )
  end

  test "suspended worker times out callers, then resumes" do
    {:ok, _} = Orchestrator.start_worker("chaos-t2", restart: :permanent)
    [{pid, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "chaos-t2")

    result =
      Chaos.suspend(pid, fn ->
        try do
          GenServer.call(
            pid,
            {:tool, ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 1}},
            200
          )
        catch
          :exit, _ -> {:error, :suspended}
        end
      end)

    assert {:error, :suspended} = result

    assert {:ok, 2} =
             AgentWorker.run_task(
               pid,
               {:tool, ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 1}}
             )
  end
end
