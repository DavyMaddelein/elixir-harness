defmodule ElixirHarness.Showcase.Isolation do
  @moduledoc "Showcase: kill one session mid-conversation; siblings keep history."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.Session

  @impl true
  def name, do: "isolation"

  @impl true
  def description, do: "Kill one Session GenServer; siblings keep every turn. No try/catch."

  @impl true
  def run do
    {:ok, s1} = Session.start_link()
    {:ok, s2} = Session.start_link()
    :ok = Session.append(s1, "user", "s1 secret")
    :ok = Session.append(s2, "user", "s2 secret")

    IO.puts("killing #{inspect(s1)} mid-conversation (unlinked first — links propagate :kill)")
    Process.unlink(s1)
    Process.exit(s1, :kill)
    Process.sleep(100)
    IO.puts("s1 alive: #{Process.alive?(s1)}")
    IO.inspect(Session.history(s2), label: "s2 remembers")
    :ok
  end
end

defmodule ElixirHarness.Showcase.Tiers do
  @moduledoc "Showcase: ETS dies with its owner, Mnesia outlives everything."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.Memory

  @impl true
  def name, do: "tiers"

  @impl true
  def description, do: "One Store behaviour, two OTP tiers: ephemeral ETS vs durable Mnesia."

  @impl true
  def run do
    parent = self()

    owner =
      spawn(fn ->
        tid = Memory.ETS.new()
        Memory.ETS.append(tid, %{role: "user", content: "hot"})
        send(parent, {:table, tid})
        Process.sleep(:infinity)
      end)

    tid =
      receive do
        {:table, t} -> t
      after
        1000 -> raise "no table"
      end

    Process.exit(owner, :kill)
    Process.sleep(100)
    IO.puts("ETS table after owner death: #{inspect(:ets.info(tid))} (gone with the process)")

    m = Memory.Mnesia.new()
    :ok = Memory.Mnesia.append(m, %{role: "user", content: "durable"})
    IO.inspect(Memory.Mnesia.list(m) |> Enum.take(-1), label: "Mnesia survives")
    Memory.Mnesia.clear(m)
    :ok
  end
end

defmodule ElixirHarness.Showcase.Budgets do
  @moduledoc "Showcase: hung tools and runaway CLIs become errors, the loop continues."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{ToolRunner, Tools}

  defmodule Sleeper do
    use ElixirHarness.Tool
    tool_name("sleeper")
    tool_description("Sleeps.")
    tool_schema(%{})
    @impl true
    def run(_),
      do:
        (
          Process.sleep(5_000)
          {:ok, :woke}
        )
  end

  @impl true
  def name, do: "budgets"

  @impl true
  def description, do: "ToolRunner timeout vs CLI max_ms kill. Everything becomes {:error}."

  @impl true
  def run do
    IO.inspect(ToolRunner.run(Sleeper, %{}, timeout: 50), label: "hung tool")

    IO.inspect(ToolRunner.run(Tools.Math, %{"op" => "add", "a" => 1, "b" => 2}),
      label: "harness continues"
    )

    IO.inspect(
      ElixirHarness.CLI.OpenCode.run("x",
        exe: "/bin/sleep",
        args: ["5"],
        append_prompt: false,
        max_ms: 50
      ),
      label: "runaway CLI"
    )

    :ok
  end
end

defmodule ElixirHarness.Showcase.Backpressure do
  @moduledoc "Showcase: bounded fan-out — concurrency is a keyword, not a queue."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{Orchestrator, ToolRunner}

  defmodule Slow do
    use ElixirHarness.Tool
    tool_name("slow")
    tool_description("Sleeps 200ms.")
    tool_schema(%{})
    @impl true
    def run(_),
      do:
        (
          Process.sleep(200)
          {:ok, :done}
        )
  end

  @impl true
  def name, do: "backpressure"

  @impl true
  def description, do: "8 slow tools, max_concurrency 2: ~800ms, not 1600 serial, no queue lib."

  @impl true
  def run do
    tasks = for _ <- 1..8, do: {Slow, %{}}

    {serial_us, _} =
      :timer.tc(fn -> Enum.each(tasks, fn {t, a} -> ToolRunner.run(t, a, timeout: 5_000) end) end)

    {bounded_us, results} =
      :timer.tc(fn -> Orchestrator.fan_out(tasks, max_concurrency: 2, timeout: 10_000) end)

    IO.puts("serial: #{div(serial_us, 1000)}ms, bounded(2): #{div(bounded_us, 1000)}ms")
    IO.puts("all ok: #{Enum.all?(results, &match?({:ok, _}, &1))}")
    :ok
  end
end

defmodule ElixirHarness.Showcase.Registry do
  @moduledoc "Showcase: named agents, no pid plumbing."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{Orchestrator, AgentWorker, Tools.Math}

  @impl true
  def name, do: "registry"

  @impl true
  def description, do: "start_worker(id) + {:via, Registry} routing. Names, not pids."

  @impl true
  def run do
    {:ok, _} = Orchestrator.start_worker("payroll")
    via = {:via, Registry, {ElixirHarness.AgentRegistry, "payroll"}}

    IO.inspect(AgentWorker.run_task(via, {:tool, Math, %{"op" => "add", "a" => 20, "b" => 2}}),
      label: "called by name through Registry"
    )

    :ok
  end
end
