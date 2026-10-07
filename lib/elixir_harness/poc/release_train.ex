defmodule ElixirHarness.Poc.ReleaseTrain do
  @moduledoc """
  Overnight release train: a role swarm (planner, coders, testers,
  reviewer, release manager) ships rate limiting + audit to a fixture
  service. Deterministic — file/shell tools stand in for model output,
  faults are scripted, no live CLIs involved.
  """

  alias ElixirHarness.{Orchestrator, Session, Toon, Plan, Cluster}
  alias ElixirHarness.Tools.{Echo, FileWrite, ShellRun, Calc}

  @rate_limiter_src ~S"""
  defmodule Checkout.RateLimiter do
    @limit 3
    def check(user_id) do
      _ = ensure_started()

      Agent.get_and_update(__MODULE__, fn counts ->
        n = Map.get(counts, user_id, 0)
        if n < @limit, do: {:allow, Map.put(counts, user_id, n + 1)}, else: {:deny, counts}
      end)
    end

    defp ensure_started do
      case Agent.start_link(fn -> %{} end, name: __MODULE__) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end
  end
  """

  @audit_src ~S"""
  defmodule Checkout.Audit do
    def record(user_id, amount_cents) do
      _ = ensure_started()
      Agent.update(__MODULE__, &Map.put(&1, user_id, amount_cents))
    end

    def last(user_id) do
      _ = ensure_started()
      Agent.get(__MODULE__, &Map.get(&1, user_id))
    end

    defp ensure_started do
      case Agent.start_link(fn -> %{} end, name: __MODULE__) do
        {:ok, _} -> :ok
        {:error, {:already_started, _}} -> :ok
      end
    end
  end
  """

  @doc "Run the train. `chaos: true` arms the scripted faults."
  @spec run(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(workdir, opts \\ []) do
    chaos? = Keyword.get(opts, :chaos, true)
    File.rm_rf!(workdir)
    File.cp_r!(fixture_dir(), workdir)

    nodes = setup_nodes(chaos?)
    sessions = start_sessions()
    :pg.join(:agents, self())

    try do
      do_run(workdir, nodes, sessions, chaos?)
    after
      if chaos?, do: teardown_nodes(nodes)
      :pg.leave(:agents, self())
    end
  end

  defp do_run(workdir, {nodes, peers}, sessions, chaos?) do
    say("planner: decomposing rate limiting + audit into a plan")
    steps = plan_steps(workdir)
    :ok = Plan.validate!("train", steps)
    Session.append(sessions.planner, "user", "ship rate limiting (3/user) + audit log")

    say("spec: recording the assignment")
    {:ok, _} = run_step(:spec, steps)

    say("coders: implementing on #{length(nodes)} node(s)")
    {:ok, coder_a} = Orchestrator.start_worker("coder-a", restart: :permanent)
    {:ok, coder_b} = Orchestrator.start_worker("coder-b", restart: :permanent)
    coder_step_a = step_for(:impl_limiter, steps, workdir)
    coder_step_b = step_for(:impl_audit, steps, workdir)

    {:ok, ra} =
      ElixirHarness.AgentWorker.run_task(coder_a, {:tool, coder_step_a.tool, coder_step_a.args})

    {:ok, rb} =
      ElixirHarness.AgentWorker.run_task(coder_b, {:tool, coder_step_b.tool, coder_step_b.args})

    Session.append(sessions.coder_a, "observation", inspect(ra))
    Session.append(sessions.coder_b, "observation", inspect(rb))

    if chaos? do
      say("chaos: kill -9 coder-a mid-train; the name must survive")
      [{pid, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "coder-a")
      Process.exit(pid, :kill)
      Process.sleep(500)
      [{pid2, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "coder-a")
      if pid2 == pid, do: raise("coder-a did not recover")
      say("chaos: coder-a #{inspect(pid)} -> #{inspect(pid2)}, re-verifying its file")

      {:ok, _} =
        ElixirHarness.AgentWorker.run_task(
          pid2,
          {:tool, FileWrite,
           %{
             "path" => Path.join(workdir, "lib/checkout/rate_limiter.ex"),
             "contents" => @rate_limiter_src
           }}
        )
    end

    if chaos? do
      [peer] = nodes -- [Node.self()]
      say("chaos: kill -9 #{peer} before the test phase")
      :ok = Cluster.stop_peer(%{node: peer, port: Map.fetch!(peers, peer)}, :kill_9)
      Process.sleep(1500)
    end

    say("testers: sharding across #{length(nodes)} node(s)")
    test_results = run_tests(workdir, nodes)
    test_results = failover(test_results, workdir)

    say("reviewer: scoring #{count_ok(test_results)}/#{length(test_results)} green shards")

    {:ok, score} =
      ElixirHarness.ToolRunner.run(Calc, %{
        "expr" => "#{count_ok(test_results)}/#{length(test_results)}"
      })

    :ok = deploy_policy(1)
    {:ok, verdict1} = ElixirHarness.ToolRunner.run(Echo, %{"text" => policy_verdict(score, 1)})
    say("chaos: hot-upgrading scoring policy v1 -> v2 mid-run")
    :ok = deploy_policy(2)
    {:ok, verdict2} = ElixirHarness.ToolRunner.run(Echo, %{"text" => policy_verdict(score, 2)})

    Session.append(
      sessions.reviewer,
      "observation",
      "score=#{score} v1=#{verdict1} v2=#{verdict2}"
    )

    unless verdict2 == "ship it" and count_ok(test_results) == length(test_results) do
      throw({:error, :train_failed})
    end

    say("release manager: TOON report + DETS snapshot")
    observations = drain_observations()
    report = build_report(test_results, score, observations)
    :ok = Session.append(sessions.manager, "assistant", "shipped")
    :ok = Session.snapshot(sessions.manager, Path.join(workdir, "release_snapshot.dets"))

    {:ok,
     %{verdict: :shipped, report: report, workdir: workdir, observations: length(observations)}}
  catch
    {:error, _} = err -> err
  end

  defp plan_steps(workdir) do
    lib = Path.join(workdir, "lib/checkout")

    [
      %{id: :spec, tool: Echo, args: %{"text" => "rate limit 3/user + audit"}, depends_on: []},
      %{
        id: :impl_limiter,
        tool: FileWrite,
        args: %{"path" => Path.join(lib, "rate_limiter.ex"), "contents" => @rate_limiter_src},
        depends_on: [:spec]
      },
      %{
        id: :impl_audit,
        tool: FileWrite,
        args: %{"path" => Path.join(lib, "audit.ex"), "contents" => @audit_src},
        depends_on: [:spec]
      },
      %{
        id: :test_unit,
        tool: ShellRun,
        args: %{
          "cmd" => "mix test test/checkout_test.exs",
          "cd" => workdir,
          "timeout_ms" => 120_000
        },
        depends_on: [:impl_limiter, :impl_audit]
      },
      %{
        id: :test_full,
        tool: ShellRun,
        args: %{"cmd" => "mix test", "cd" => workdir, "timeout_ms" => 120_000},
        depends_on: [:impl_limiter, :impl_audit]
      }
    ]
  end

  defp step_for(id, steps, _workdir), do: Enum.find(steps, &(&1.id == id))

  defp run_step(id, steps) do
    %{tool: tool, args: args} = Enum.find(steps, &(&1.id == id))
    ElixirHarness.ToolRunner.run(tool, args, timeout: 10_000)
  end

  defp run_tests(workdir, nodes) do
    shards = [
      {ShellRun,
       %{"cmd" => "mix test test/checkout_test.exs", "cd" => workdir, "timeout_ms" => 120_000}},
      {ShellRun, %{"cmd" => "mix test", "cd" => workdir, "timeout_ms" => 120_000}}
    ]

    Orchestrator.fan_out(shards,
      nodes: cycle_nodes(nodes, 2),
      max_concurrency: 2,
      timeout: 150_000
    )
  end

  defp cycle_nodes(nodes, n), do: nodes |> Stream.cycle() |> Enum.take(n)

  defp failover(results, workdir) do
    if Enum.any?(results, &match?({:error, {:badrpc, _}}, &1)) do
      say("failover: re-running dead-node shards locally")

      redo =
        for {:error, {:badrpc, _}} <- results,
            do: {ShellRun, %{"cmd" => "mix test", "cd" => workdir, "timeout_ms" => 120_000}}

      good = Enum.reject(results, &match?({:error, {:badrpc, _}}, &1))
      good ++ Orchestrator.fan_out(redo, nodes: [Node.self()], timeout: 150_000)
    else
      results
    end
  end

  defp count_ok(results), do: Enum.count(results, &match?({:ok, _}, &1))

  defp setup_nodes(false), do: {[Node.self()], %{}}

  defp setup_nodes(true) do
    {:ok, _} = Cluster.ensure_distributed()
    {:ok, peer} = Cluster.start_peer(peer_name())
    :ok = Cluster.ensure_app(peer.node)
    {[Node.self(), peer.node], %{peer.node => peer.port}}
  end

  defp teardown_nodes({nodes, peers}) do
    for node <- nodes -- [Node.self()] do
      port = Map.get(peers, node)

      if port do
        :ok = Cluster.stop_peer(%{node: node, port: port}, :graceful)
      else
        :rpc.call(node, :init, :stop, [])
      end
    end

    :ok
  end

  defp peer_name, do: :"train_peer#{System.unique_integer([:positive])}"

  defp fixture_dir, do: Path.expand("../../../poc/fixtures/checkout", __DIR__)

  defp start_sessions do
    {:ok, planner} = Session.start_link()
    {:ok, coder_a} = Session.start_link()
    {:ok, coder_b} = Session.start_link()
    {:ok, reviewer} = Session.start_link()
    {:ok, manager} = Session.start_link()
    %{planner: planner, coder_a: coder_a, coder_b: coder_b, reviewer: reviewer, manager: manager}
  end

  defp drain_observations do
    receive do
      {:observation, obs} -> [obs | drain_observations()]
    after
      2_000 -> []
    end
  end

  defp build_report(results, score, observations) do
    rows =
      results
      |> Enum.with_index(1)
      |> Enum.map(fn
        {{:ok, out}, i} ->
          %{"shard" => i, "status" => "green", "detail" => String.slice(out, -60, 60)}

        {{:error, reason}, i} ->
          %{"shard" => i, "status" => "red", "detail" => inspect(reason) |> String.slice(0, 60)}
      end)

    Toon.encode_stream(
      rows ++
        [
          %{
            "shard" => 0,
            "status" => "score=#{score}",
            "detail" => "#{length(observations)} observations"
          }
        ],
      "shards", chunk_size: 10)
    |> Enum.join("\n")
  end

  defp deploy_policy(vsn) do
    src = """
    defmodule ElixirHarness.Poc.Policy do
      def threshold, do: #{if vsn == 1, do: "0.5", else: "0.9"}
      def version, do: #{vsn}
    end
    """

    ElixirHarness.Showcase.Upgrade.deploy_source(ElixirHarness.Poc.Policy, src)
  end

  defp policy_verdict(score, vsn) do
    threshold = if vsn == 1, do: 0.5, else: 0.9
    if score >= threshold, do: "ship it", else: "hold"
  end

  defp say(line), do: IO.puts("train> #{line}")

  def rate_limiter_src, do: @rate_limiter_src
  def audit_src, do: @audit_src
end
