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

  @impl true
  def init(id) do
    :pg.join(:agents, self())
    {:ok, %{id: id}}
  end

  @impl true
  def handle_call({:tool, tool, args}, _from, state) do
    {:reply, ElixirHarness.ToolRunner.run(tool, args), state}
  end
end

defmodule ElixirHarness.Orchestrator do
  @moduledoc """
  Multi-agent fan-out: DynamicSupervisor workers, Registry lookup,
  `:pg` groups, `Task.async_stream` with backpressure.
  """

  @spec start_worker(term()) :: DynamicSupervisor.on_start_child()
  def start_worker(id) do
    DynamicSupervisor.start_child(
      ElixirHarness.AgentSupervisor,
      %{id: id, start: {ElixirHarness.AgentWorker, :start_link, [id]}, restart: :temporary}
    )
  end

  @spec members() :: [pid()]
  def members, do: :pg.get_members(:agents)

  @doc "Fan out `{tool, args}` tasks across workers. Crashes become errors, not batch failures."
  @spec fan_out([{module(), map()}], keyword()) :: [{:ok, term()} | {:error, term()}]
  def fan_out(tasks, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)
    timeout = Keyword.get(opts, :timeout, 15_000)

    tasks
    |> Task.async_stream(
      fn {tool, args} ->
        {:ok, worker} = start_worker(make_ref())
        ElixirHarness.AgentWorker.run_task(worker, {:tool, tool, args})
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
end

defmodule ElixirHarness.Cluster do
  @moduledoc "Distribution stub: run a call on another node, same API as local."

  @spec rpc(node(), module(), atom(), list()) :: term() | {:badrpc, term()}
  def rpc(node, mod, fun, args) do
    if node == Node.self(), do: apply(mod, fun, args), else: :rpc.call(node, mod, fun, args)
  end
end
