defmodule ElixirHarness.Dashboard do
  @moduledoc "Boots mission control: PubSub + Endpoint + telemetry bridge."

  @spec boot(pos_integer()) :: {:ok, pid()}
  def boot(port \\ 4000) do
    unless Code.ensure_loaded?(Phoenix.Endpoint) do
      raise ArgumentError,
            "mission control needs the dashboard deps (phoenix, phoenix_live_view, phoenix_pubsub, bandit); the harness core runs without them"
    end

    Application.put_env(:elixir_harness, ElixirHarnessWeb.Endpoint,
      url: [host: "localhost"],
      http: [port: port],
      server: true,
      adapter: Bandit.PhoenixAdapter,
      secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48)),
      live_view: [signing_salt: Base.encode64(:crypto.strong_rand_bytes(24))],
      pubsub_server: ElixirHarness.PubSub
    )

    children = [
      {Phoenix.PubSub, name: ElixirHarness.PubSub},
      ElixirHarnessWeb.Endpoint
    ]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)
    ElixirHarness.Dashboard.TelemetryBridge.attach()
    {:ok, sup}
  end
end

defmodule ElixirHarness.Dashboard.Introspect do
  @moduledoc """
  Pure data for mission control. Every number is a BEAM introspection
  call — `Supervisor.which_children`, `:pg`, `Process` — no agents,
  no polling daemons.
  """

  @doc "Recursive supervision tree from the app root."
  @spec tree(Supervisor.supervisor()) :: [map()]
  def tree(sup \\ ElixirHarness.Supervisor) do
    children =
      try do
        Supervisor.which_children(sup)
      rescue
        _ -> []
      catch
        _, _ -> []
      end

    for {id, pid, type, _mods} <- children do
      alive = is_pid(pid) and Process.alive?(pid)

      %{
        id: inspect(id),
        pid: inspect(pid),
        alive: alive,
        children: if(type == :supervisor and alive, do: tree(pid), else: [])
      }
    end
  end

  @doc "Live agent workers with `:pg` membership."
  @spec workers() :: [map()]
  def workers do
    members =
      try do
        :pg.get_members(:agents)
      rescue
        _ -> []
      end

    for {_id, pid, _, _} <- DynamicSupervisor.which_children(ElixirHarness.AgentSupervisor),
        Process.alive?(pid) do
      %{id: inspect(safe_id(pid)), pid: inspect(pid), in_pg: pid in members}
    end
  end

  defp safe_id(pid) do
    try do
      ElixirHarness.AgentWorker.id(pid)
    catch
      _, _ -> :unknown
    end
  end

  @doc " BEAM scheduler / process counts for the header strip."
  @spec vm_stats() :: map()
  def vm_stats do
    %{
      processes: :erlang.system_info(:process_count),
      schedulers: :erlang.system_info(:schedulers_online),
      nodes: [Node.self() | Node.list()]
    }
  end
end

defmodule ElixirHarness.Dashboard.TelemetryBridge do
  @moduledoc "Forwards harness `:telemetry` events to the dashboard PubSub topic."

  @topic "dashboard:events"
  @handler_id "dashboard-bridge"

  @events [
    [:elixir_harness, :tool, :run],
    [:elixir_harness, :toon, :encode, :stop],
    [:elixir_harness, :toon, :decode, :stop]
  ]

  def topic, do: @topic

  def attach do
    :telemetry.detach(@handler_id)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle/4, nil)
  end

  def handle([:elixir_harness, :tool, :run], %{duration_ms: ms}, %{tool: tool, ok: ok}, _) do
    broadcast({:tool_run, %{tool: tool, ok: ok, ms: ms, at: DateTime.utc_now()}})
  end

  def handle([:elixir_harness, :toon, event, :stop], _measurements, _meta, _) do
    broadcast({:toon_event, %{event: event, at: DateTime.utc_now()}})
  end

  defp broadcast(msg) do
    Phoenix.PubSub.broadcast(ElixirHarness.PubSub, @topic, msg)
  end
end
