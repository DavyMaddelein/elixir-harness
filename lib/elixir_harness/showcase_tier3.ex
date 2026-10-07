defmodule ElixirHarness.Showcase.Streaming do
  @moduledoc "Showcase: 10k history rows to TOON without one giant binary."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.Toon

  @impl true
  def name, do: "streaming"

  @impl true
  def description, do: "Stream 10k rows through chunked TOON encoding. No giant prompt binary."

  @impl true
  def run do
    rows = for i <- 1..10_000, do: %{"id" => i, "role" => "user", "content" => "message #{i}"}
    chunks = rows |> Toon.encode_stream("history", chunk_size: 500) |> Enum.to_list()
    IO.puts("10k rows -> #{length(chunks)} self-contained TOON documents")
    IO.puts("first chunk head: #{chunks |> hd() |> String.split("\n") |> hd()}")

    IO.puts(
      "largest chunk: #{chunks |> Enum.map(&byte_size/1) |> Enum.max()} bytes (bounded by chunk size, not history)"
    )

    :ok
  end
end

defmodule ElixirHarness.Showcase.Telemetry do
  @moduledoc "Showcase: vendor-free metrics — attach, run, count."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{ToolRunner, Tools, Toon}

  @impl true
  def name, do: "telemetry"

  @impl true
  def description, do: "Attach a :telemetry handler, run tools, count spans. No vendor SDK."

  @impl true
  def run do
    me = self()

    :telemetry.attach_many(
      "showcase-telemetry",
      [[:elixir_harness, :tool, :run], [:elixir_harness, :toon, :encode, :stop]],
      &__MODULE__.handle/4,
      me
    )

    ToolRunner.run(Tools.Math, %{"op" => "add", "a" => 1, "b" => 2})
    ToolRunner.run(Tools.Echo, %{"text" => "hi"})
    Toon.encode!(%{"a" => 1})
    events = collect([])
    :telemetry.detach("showcase-telemetry")

    IO.inspect(events, label: "spans observed")
    :ok
  end

  @doc false
  def handle(event, %{duration_ms: _}, _meta, pid) do
    send(pid, {:event, event})
  end

  def handle(event, _measurements, _meta, pid) do
    send(pid, {:event, event})
  end

  defp collect(acc) do
    receive do
      {:event, e} -> collect([e | acc])
    after
      200 -> Enum.reverse(acc)
    end
  end
end

defmodule ElixirHarness.Showcase.Restarts do
  @moduledoc "Showcase: restart semantics are a flag, not code."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{Orchestrator, AgentWorker}

  @impl true
  def name, do: "restarts"

  @impl true
  def description,
    do: ":temporary workers vanish by design; :permanent ones come back. Same starter."

  @impl true
  def run do
    {:ok, _} = Orchestrator.start_worker("temp-w", restart: :temporary)
    [{temp, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "temp-w")
    Process.exit(temp, :kill)
    Process.sleep(200)

    IO.puts(
      "temporary after kill: #{inspect(Registry.lookup(ElixirHarness.AgentRegistry, "temp-w"))} (gone by design)"
    )

    {:ok, _} = Orchestrator.start_worker("perm-w", restart: :permanent)
    [{perm, _}] = Registry.lookup(ElixirHarness.AgentRegistry, "perm-w")
    Process.exit(perm, :kill)
    Process.sleep(300)

    IO.inspect(Registry.lookup(ElixirHarness.AgentRegistry, "perm-w"),
      label: "permanent after kill"
    )

    IO.inspect(
      AgentWorker.run_task(
        "perm-w" |> worker_pid!(),
        {:tool, ElixirHarness.Tools.Math, %{"op" => "add", "a" => 1, "b" => 1}}
      ), label: "serves again")

    :ok
  end

  defp worker_pid!(id) do
    [{pid, _}] = Registry.lookup(ElixirHarness.AgentRegistry, id)
    pid
  end
end
