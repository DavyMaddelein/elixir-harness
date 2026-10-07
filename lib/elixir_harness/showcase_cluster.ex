defmodule ElixirHarness.Showcase.Cluster do
  @moduledoc "Showcase: one batch, two BEAM nodes, then kill -9 one of them."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{Cluster, Orchestrator, Tools.Math}

  @impl true
  def name, do: "cluster"

  @impl true
  def description,
    do: "Fan-out across two real BEAM nodes; kill -9 one mid-batch and the batch still completes."

  @impl true
  def run do
    say("1. Going distributed (shortnames, local epmd — no containers).")
    {:ok, _} = Cluster.ensure_distributed()

    say("2. Booting a full Elixir peer node as an OS process.")
    {:ok, peer} = Cluster.start_peer(peer_name())
    :ok = Cluster.ensure_app(peer.node)
    say("   peer up: #{peer.node}")

    tasks = for i <- 1..6, do: {Math, %{"op" => "add", "a" => i, "b" => 0}}

    say("3. Fan-out across [self, peer] — same API, :rpc underneath.")
    results = Orchestrator.fan_out(tasks, nodes: [Node.self(), peer.node], max_concurrency: 6)
    say("   #{count_ok(results)}/#{length(results)} ok")

    say("4. Monitor the peer, kill -9 it, watch :nodedown arrive — then run the batch again.")
    true = Node.monitor(peer.node, true)
    :ok = Cluster.stop_peer(peer, :kill_9)

    receive do
      {:nodedown, node} -> say("   :nodedown #{node} — the VM told us, no heartbeat lib")
    after
      10_000 -> say("   (no nodedown within 10s)")
    end

    Process.sleep(1500)
    results2 = Orchestrator.fan_out(tasks, nodes: [Node.self(), peer.node], max_concurrency: 6)

    say(
      "   #{count_ok(results2)}/#{length(results2)} ok, #{count_err(results2)} node-down errors — batch completes anyway"
    )

    :ok
  end

  defp peer_name, do: :"harness_peer#{System.unique_integer([:positive])}"

  defp count_ok(results), do: Enum.count(results, &match?({:ok, _}, &1))
  defp count_err(results), do: Enum.count(results, &match?({:error, _}, &1))

  defp say(line), do: IO.puts(line)
end

defmodule Mix.Tasks.Showcase do
  @shortdoc "Run a showcase: mix showcase [name]"
  use Mix.Task

  @impl true
  def run([]) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)

    for mod <- ElixirHarness.Showcase.all() do
      Mix.shell().info("#{mod.name()} — #{mod.description()}")
    end
  end

  def run([name]) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)

    case ElixirHarness.Showcase.find(name) do
      {:ok, mod} -> mod.run()
      :error -> Mix.raise("unknown showcase #{inspect(name)}; run `mix showcase` to list")
    end
  end
end
