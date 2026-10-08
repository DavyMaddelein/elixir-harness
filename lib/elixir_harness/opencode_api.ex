defmodule ElixirHarness.CLI.OpenCodeAPI do
  @moduledoc """
  opencode HTTP adapter behind the `CLIAdapter` behaviour.

  One `run/2` = ensure session → POST prompt → poll messages until the
  assistant turn completes → return its text. Budgets interrupt the
  session instead of killing a process. Diffs verify what changed.
  """
  @behaviour ElixirHarness.CLIAdapter

  alias ElixirHarness.CLI.OpenCode.Http

  @impl true
  def run(prompt, opts \\ []) do
    server = Keyword.fetch!(opts, :server)
    max_ms = Keyword.get(opts, :max_ms, 120_000)
    interval = Keyword.get(opts, :poll_interval_ms, 500)

    with {:ok, session_id} <- ensure_session(server, opts),
         {:ok, _} <- Http.post(server, "/api/session/#{session_id}/prompt", %{text: prompt}) do
      collect(server, session_id, System.monotonic_time(:millisecond) + max_ms, interval, nil)
    end
  end

  @doc "List assistant text of a session (oldest first)."
  @spec transcript(map(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def transcript(server, session_id) do
    case Http.get(server, "/api/session/#{session_id}/message") do
      {:ok, %{"data" => messages}} -> {:ok, assistant_texts(messages)}
      {:ok, other} -> {:error, {:unexpected_shape, other}}
      {:error, _} = err -> err
    end
  end

  @doc "Interrupt a running session (budget enforcement with manners)."
  @spec interrupt(map(), String.t()) :: :ok | {:error, term()}
  def interrupt(server, session_id) do
    case Http.post(server, "/api/session/#{session_id}/interrupt", %{}) do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @doc "Diff of what the session changed. Ideal for test assertions."
  @spec diff(map(), String.t()) :: {:ok, term()} | {:error, term()}
  def diff(server, session_id) do
    Http.get(server, "/api/session/#{session_id}/diff")
  end

  defp ensure_session(server, opts) do
    case Keyword.get(opts, :session_id) do
      nil ->
        case Http.post(server, "/api/session", %{
               title: Keyword.get(opts, :title, "elixir-harness")
             }) do
          {:ok, %{"id" => id}} -> {:ok, id}
          {:ok, other} -> {:error, {:unexpected_shape, other}}
          {:error, _} = err -> err
        end

      id ->
        {:ok, id}
    end
  end

  defp collect(server, session_id, deadline, interval, _last) do
    if System.monotonic_time(:millisecond) > deadline do
      _ = interrupt(server, session_id)
      {:error, :budget_time_exceeded}
    else
      case transcript(server, session_id) do
        {:ok, [_ | _] = texts} ->
          if settled?(server, session_id, texts, interval),
            do: {:ok, Enum.join(texts, "\n")},
            else:
              (
                Process.sleep(interval)
                collect(server, session_id, deadline, interval, texts)
              )

        {:ok, []} ->
          Process.sleep(interval)
          collect(server, session_id, deadline, interval, nil)

        {:error, _} = err ->
          err
      end
    end
  end

  defp settled?(server, session_id, texts, interval) do
    Process.sleep(interval)

    case transcript(server, session_id) do
      {:ok, texts2} -> texts2 == texts
      _ -> false
    end
  end

  defp assistant_texts(messages) do
    for %{"type" => "assistant", "content" => parts} <- messages,
        %{"type" => "text", "text" => text} <- parts,
        do: text
  end
end
