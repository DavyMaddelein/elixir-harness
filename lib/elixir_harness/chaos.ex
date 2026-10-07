defmodule ElixirHarness.Chaos do
  @moduledoc """
  Fault injection for demos: suspend, kill, and ordered restarts.
  Everything here uses stock OTP — no chaos-monkey library.
  """

  @doc "Suspend `pid`, run `fun`, always resume afterwards."
  @spec suspend(pid(), (-> term())) :: term()
  def suspend(pid, fun) do
    :ok = :sys.suspend(pid)

    try do
      fun.()
    after
      :ok = :sys.resume(pid)
    end
  end
end

defmodule ElixirHarness.Restarter do
  @moduledoc """
  Ordered-dependency example: `rest_for_one` means killing child `:b`
  restarts `:b` AND everything after it (`:c`), but not `:a`.
  """
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    children =
      for id <- [:a, :b, :c] do
        %{id: id, start: {Agent, :start_link, [fn -> id end, []]}}
      end

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Child pids in start order."
  @spec pids(Supervisor.supervisor()) :: [pid()]
  def pids(sup) do
    sup
    |> Supervisor.which_children()
    |> Enum.sort_by(fn {id, _, _, _} -> id end)
    |> Enum.map(&elem(&1, 1))
  end
end

defmodule ElixirHarness.Showcase.Chaos do
  @moduledoc "Showcase: kill, suspend, and ordered restarts — all recovered."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{Orchestrator, AgentWorker, Chaos, Restarter}

  @impl true
  def name, do: "chaos"

  @impl true
  def description,
    do: "Kill and suspend workers mid-flight; rest_for_one ordering. All recovered."

  @impl true
  def run do
    IO.puts("1. A permanent worker dies by kill -9 and comes back under the same name.")
    {:ok, _} = Orchestrator.start_worker("chaos-w1", restart: :permanent)
    [{pid, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "chaos-w1")
    Process.exit(pid, :kill)
    Process.sleep(500)
    [{pid2, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "chaos-w1")
    IO.puts("   #{inspect(pid)} -> #{inspect(pid2)} (restarted, same name)")

    IO.inspect(
      AgentWorker.run_task(
        pid2,
        {:tool, ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 2}}
      ), label: "   serves again")

    IO.puts("2. A suspended worker times out its caller, then resumes cleanly.")
    {:ok, _} = Orchestrator.start_worker("chaos-w2", restart: :permanent)
    [{pid3, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "chaos-w2")

    suspended_result =
      Chaos.suspend(pid3, fn ->
        try do
          GenServer.call(
            pid3,
            {:tool, ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 1}},
            200
          )
        catch
          :exit, _ -> {:error, :suspended}
        end
      end)

    IO.inspect(suspended_result, label: "   while suspended")

    IO.inspect(
      AgentWorker.run_task(
        pid3,
        {:tool, ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 1}}
      ), label: "   after resume")

    IO.puts("3. rest_for_one: killing :b restarts :b and :c, never :a.")
    {:ok, sup} = Restarter.start_link()
    [a, b, _c] = Restarter.pids(sup)
    Process.exit(b, :kill)
    Process.sleep(300)
    [a2, b2, c2] = Restarter.pids(sup)

    IO.puts(
      "   a same: #{a == a2}, b restarted: #{b != b2}, c restarted too: #{c2 not in [a, b]}"
    )

    :ok
  end
end
