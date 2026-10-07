defmodule ElixirHarnessWeb.Json do
  @moduledoc """
  Phoenix JSON adapter over OTP's built-in `:json` module.
  Keeps Jason out of the tree entirely — sockets included.
  """

  def decode!(binary), do: :json.decode(binary)
  def encode!(term), do: term |> encode_to_iodata!() |> IO.iodata_to_binary()
  def encode_to_iodata!(term), do: :json.encode(term)
end

defmodule ElixirHarnessWeb.ErrorHTML do
  use Phoenix.Component

  def render("404.html", _), do: "not found"
  def render("500.html", _), do: "internal error"
end

defmodule ElixirHarnessWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>ElixirHarness Mission Control</title>
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.8.0/priv/static/phoenix.min.js">
        </script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@1.1.0/priv/static/phoenix_live_view.min.js">
        </script>
        <script>
          let liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {});
          liveSocket.connect();
        </script>
        <style>
          body { font-family: monospace; max-width: 1000px; margin: 2em auto; padding: 0 1em; }
          section { border: 1px solid #ccc; padding: 1em; margin-bottom: 1em; }
          .ok { color: green; } .err { color: red; }
          pre { background: #f4f4f4; padding: 1em; overflow-x: auto; }
          button { font-family: monospace; margin-right: 0.5em; }
        </style>
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end
end

defmodule ElixirHarnessWeb.MissionLive do
  use Phoenix.LiveView

  alias ElixirHarness.Dashboard.{Introspect, TelemetryBridge}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ElixirHarness.PubSub, TelemetryBridge.topic())
      Process.send_after(self(), :tick, 1000)
    end

    {:ok, refresh(assign(socket, log: [], prompt: nil))}
  end

  @impl true
  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1000)
    {:noreply, refresh(socket)}
  end

  def handle_info({:tool_run, e}, socket) do
    {:noreply, update(socket, :log, &[e | Enum.take(&1, 29)])}
  end

  def handle_info({:toon_event, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("traffic", _params, socket) do
    Task.start(fn ->
      tasks = for i <- 1..6, do: {ElixirHarness.Tools.Math, %{"op" => "add", "a" => i, "b" => 0}}
      ElixirHarness.Orchestrator.fan_out(tasks, max_concurrency: 6)
    end)

    {:noreply, socket}
  end

  def handle_event("session", _params, socket) do
    {:ok, s} = ElixirHarness.Session.start_link()
    :ok = ElixirHarness.Session.append(s, "user", "deploy friday?")
    :ok = ElixirHarness.Session.append(s, "assistant", "only with a rollback plan")
    {:noreply, assign(socket, prompt: ElixirHarness.Session.to_prompt(s))}
  end

  defp refresh(socket) do
    assign(socket,
      tree: Introspect.tree(),
      workers: Introspect.workers(),
      vm: Introspect.vm_stats()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>ElixirHarness Mission Control</h1>
    <p>
      node <%= inspect(@vm.nodes) %> · <%= @vm.processes %> processes · <%= @vm.schedulers %> schedulers
    </p>
    <p>
      <button phx-click="traffic">Generate traffic</button>
      <button phx-click="session">New demo session</button>
    </p>
    <section>
      <h2>Supervision tree</h2>
      <.tree nodes={@tree} />
    </section>
    <section>
      <h2>Agent workers ({length(@workers)})</h2>
      <ul>
        <li :for={w <- @workers}><%= w.id %> · <%= w.pid %> · pg: <%= w.in_pg %></li>
      </ul>
    </section>
    <section>
      <h2>Tool runs (live via telemetry → PubSub)</h2>
      <ul>
        <li :for={e <- @log}>
          <span class={if e.ok, do: "ok", else: "err"}><%= if e.ok, do: "ok", else: "ERR" %></span>
          <%= e.tool %> · <%= e.ms %>ms
        </li>
      </ul>
    </section>
    <section :if={@prompt}>
      <h2>Session prompt (TOON)</h2>
      <pre><%= @prompt %></pre>
    </section>
    """
  end

  defp tree(assigns) do
    ~H"""
    <ul>
      <li :for={n <- @nodes}>
        <%= n.id %> · <%= n.pid %>
        <.tree nodes={n.children} :if={n.children != []} />
      </li>
    </ul>
    """
  end
end

defmodule ElixirHarnessWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:put_root_layout, {ElixirHarnessWeb.Layouts, :root})
  end

  scope "/", ElixirHarnessWeb do
    pipe_through(:browser)
    live("/", MissionLive)
  end
end

defmodule ElixirHarnessWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :elixir_harness

  socket("/live", Phoenix.LiveView.Socket)
  plug(ElixirHarnessWeb.Router)
end
