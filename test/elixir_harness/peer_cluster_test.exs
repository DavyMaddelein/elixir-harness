defmodule ElixirHarness.PeerClusterTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.{PeerCluster, Orchestrator, Tools.Math}

  @moduletag timeout: 120_000

  test "peer boots, joins, runs tools, and stops with the test" do
    on_exit(fn ->
      if Node.alive?(), do: Node.stop()
      :ok
    end)

    {:ok, _} = PeerCluster.ensure_distributed()
    {:ok, peer} = PeerCluster.start_peer()
    assert peer.node in Node.list()

    tasks = for i <- 1..4, do: {Math, %{"op" => "add", "a" => i, "b" => 0}}
    results = Orchestrator.fan_out(tasks, nodes: [Node.self(), peer.node])
    assert Enum.all?(results, &match?({:ok, _}, &1))

    :ok = PeerCluster.stop_peer(peer)
    refute peer.node in Node.list()
  end
end
