defmodule ElixirHarness.AgentWorker do
  @moduledoc "One supervised agent. Joins the `:agents` :pg group on start."
  use GenServer

  def start_link(id) do
    GenServer.start_link(__MODULE__, id,
      name: {:via, Registry, {ElixirHarness.AgentRegistry, id}}
    )
  end

  def run_task(worker, {:tool, tool, args}) do
    GenServer.call(worker, {:tool, tool, args}, 15_000)
  end

  def id(worker) do
    GenServer.call(worker, :id)
  end

  @impl true
  def init(id) do
    :pg.join(:agents, self())
    {:ok, %{id: id}}
  end

  @impl true
  def handle_call({:tool, tool, args}, _from, state) do
    {:reply, ElixirHarness.ToolRunner.run(tool, args), state}
  end

  def handle_call(:id, _from, %{id: id} = state) do
    {:reply, id, state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}
end

defmodule ElixirHarness.Orchestrator do
  @moduledoc """
  Multi-agent fan-out: DynamicSupervisor workers, Registry lookup,
  `:pg` groups, `Task.async_stream` with backpressure.
  """

  @spec start_worker(term(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_worker(id, opts \\ []) do
    restart = Keyword.get(opts, :restart, :temporary)

    DynamicSupervisor.start_child(
      ElixirHarness.AgentSupervisor,
      %{id: id, start: {ElixirHarness.AgentWorker, :start_link, [id]}, restart: restart}
    )
  end

  @spec members() :: [pid()]
  def members, do: :pg.get_members(:agents)

  @doc """
  Fan out `{tool, args}` tasks across supervised workers.

  Pass `nodes: [node1, node2]` to spread work across the cluster —
  remote workers start under the remote `DynamicSupervisor` and are
  driven over transparent distribution. Dead nodes become
  `{:error, {:badrpc, _}}` entries, not batch failures.
  """
  @spec fan_out([{module(), map()}], keyword()) :: [{:ok, term()} | {:error, term()}]
  def fan_out(tasks, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)
    timeout = Keyword.get(opts, :timeout, 15_000)
    nodes = Keyword.get(opts, :nodes, [Node.self()])

    tasks
    |> Enum.with_index()
    |> Task.async_stream(
      fn {{tool, args}, i} ->
        result = run_on(Enum.at(nodes, rem(i, length(nodes))), tool, args)
        # :pg is membership; delivery is plain send. No pubsub dep.
        for pid <- :pg.get_members(:agents) do
          send(pid, {:observation, %{tool: tool.tool_name(), result: result}})
        end

        result
      end,
      max_concurrency: max_concurrency,
      ordered: false,
      timeout: timeout
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:exit, reason}}
    end)
  end

  defp run_on(node, tool, args) do
    if node == Node.self() do
      {:ok, worker} = start_worker(make_ref())
      ElixirHarness.AgentWorker.run_task(worker, {:tool, tool, args})
    else
      spec = %{
        id: make_ref(),
        start: {ElixirHarness.AgentWorker, :start_link, [make_ref()]},
        restart: :temporary
      }

      case :rpc.call(node, DynamicSupervisor, :start_child, [ElixirHarness.AgentSupervisor, spec]) do
        {:ok, pid} ->
          try do
            GenServer.call(pid, {:tool, tool, args}, 15_000)
          catch
            :exit, reason -> {:error, {:exit, reason}}
          end

        {:badrpc, _} = err ->
          {:error, err}

        {:error, _} = err ->
          {:error, err}
      end
    end
  end
end
