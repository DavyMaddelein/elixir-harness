defmodule ElixirHarness.ClusterTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.{Cluster, Orchestrator, Tools.Math}

  @moduletag timeout: 120_000

  test "fan-out spans two nodes and survives kill -9" do
    {:ok, _} = Cluster.ensure_distributed(:"harness_test#{System.unique_integer([:positive])}")
    {:ok, peer} = Cluster.start_peer(:"harness_tpeer#{System.unique_integer([:positive])}", timeout: 60_000)
    :ok = Cluster.ensure_app(peer.node)

    tasks = for i <- 1..4, do: {Math, %{"op" => "add", "a" => i, "b" => 0}}
    assert [ok: _, ok: _, ok: _, ok: _] = Orchestrator.fan_out(tasks, nodes: [Node.self(), peer.node]) |> Enum.sort()

    :ok = Cluster.stop_peer(peer, :kill_9)
    Process.sleep(1500)

    results = Orchestrator.fan_out(tasks, nodes: [Node.self(), peer.node])
    assert Enum.count(results, &match?({:ok, _}, &1)) == 2
    assert Enum.count(results, &match?({:error, _}, &1)) == 2
  end

  test "cluster rpc runs locally on self node" do
    assert 3 = Cluster.rpc(Node.self(), Kernel, :+, [1, 2])
  end
end
