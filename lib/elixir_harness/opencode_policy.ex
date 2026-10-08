defmodule ElixirHarness.CLI.OpenCodePolicy do
  @moduledoc """
  Autonomous permission replies: polls a session's pending requests and
  answers from an allowlist policy. Anything unmatched is rejected —
  deny by default, because unattended agents should fail closed.
  """

  use GenServer

  alias ElixirHarness.CLI.OpenCode.Http

  @doc """
  Start the loop. Policy: `%{rules: [{action, resource_pattern, reply}]}`,
  where reply is `"once"`, `"always"` or `"reject"`. Patterns match by
  equality or `Regex`.
  """
  @spec start_link(map(), String.t(), map(), keyword()) :: GenServer.on_start()
  def start_link(server, session_id, policy, opts \\ []) do
    GenServer.start_link(__MODULE__, {server, session_id, policy}, opts)
  end

  @impl true
  def init({server, session_id, policy}) do
    Process.send_after(self(), :poll, 100)
    {:ok, %{server: server, session_id: session_id, policy: policy}}
  end

  @impl true
  def handle_info(:poll, state) do
    _ = settle(state)
    Process.send_after(self(), :poll, 500)
    {:noreply, state}
  end

  @doc "Decide a reply for one request under the policy."
  @spec decide(map(), map()) :: String.t()
  def decide(%{"action" => action, "resources" => resources}, %{rules: rules}) do
    if Enum.any?(rules, &rule_matches?(&1, action, resources)), do: "once", else: "reject"
  end

  defp rule_matches?({action_pat, resource_pat, "once"}, action, resources) do
    matches?(action_pat, action) and Enum.any?(resources, &matches?(resource_pat, &1))
  end

  defp rule_matches?(_, _, _), do: false

  defp matches?(pat, value) when is_binary(pat), do: pat == value
  defp matches?(%Regex{} = pat, value), do: Regex.match?(pat, value)

  defp settle(%{server: server, session_id: sid, policy: policy}) do
    case Http.get(server, "/api/session/#{sid}/permission") do
      {:ok, requests} when is_list(requests) ->
        for %{"id" => id} = req <- requests do
          _ =
            Http.post(server, "/api/session/#{sid}/permission/#{id}/reply", %{
              reply: decide(req, policy)
            })
        end

        :ok

      _ ->
        :ok
    end
  end
end

defmodule ElixirHarness.CLI.OpenCodeEvents do
  @moduledoc """
  Forwards the server's SSE stream to PubSub topic `"opencode:events"`.
  Mission control subscribes; agent output appears live.
  """
  use GenServer

  alias ElixirHarness.CLI.OpenCode.Http

  @topic "opencode:events"

  def topic, do: @topic

  @spec start_link(map(), keyword()) :: GenServer.on_start()
  def start_link(server, opts \\ []) do
    GenServer.start_link(__MODULE__, server, opts)
  end

  @impl true
  def init(server) do
    {:ok, %{server: server}, {:continue, :subscribe}}
  end

  @impl true
  def handle_continue(:subscribe, %{server: server} = state) do
    parent = self()

    Task.start(fn ->
      Http.sse(server, "/api/event", fn event -> send(parent, {:server_event, event}) end,
        max_ms: :infinity
      )
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:server_event, event}, state) do
    Phoenix.PubSub.broadcast(ElixirHarness.PubSub, @topic, {:opencode_event, event})
    {:noreply, state}
  end
end
