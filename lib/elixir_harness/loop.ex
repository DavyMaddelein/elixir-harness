defmodule ElixirHarness.Loop do
  @moduledoc """
  ReAct agent loop: prompt -> CLI -> tool_call -> observe -> repeat.

  Reply contract (TOON-decoded map):
  - `%{"action" => "final", "content" => text}`
  - `%{"action" => "tool_call", "tool" => name, "args" => map}`

  Strict TOON decode failure triggers a retry, never execution.
  Budgets: `max_iters`, `max_retries`, `tool_timeout`.
  """
  alias ElixirHarness.{Session, ToolRunner, Toon}

  @spec run(pid(), module(), [module()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(session, adapter, tools, opts \\ []) do
    max_iters = Keyword.get(opts, :max_iters, 5)
    max_retries = Keyword.get(opts, :max_retries, 2)
    adapter_opts = Keyword.get(opts, :adapter_opts, [])
    tool_timeout = Keyword.get(opts, :tool_timeout, 5_000)
    by_name = Map.new(tools, &{&1.tool_name(), &1})
    step(session, adapter, adapter_opts, by_name, max_iters, max_retries, tool_timeout)
  end

  defp step(_s, _a, _ao, _t, 0, _r, _tt), do: {:error, :max_iters}

  defp step(session, adapter, adapter_opts, tools, iters, retries, tool_timeout) do
    prompt = build_prompt(session, Map.values(tools))

    case adapter.run(prompt, adapter_opts) do
      {:error, reason} ->
        {:error, {:adapter, reason}}

      {:ok, raw} ->
        case Toon.decode(raw) do
          {:ok, reply} ->
            handle_reply(
              session,
              adapter,
              adapter_opts,
              tools,
              iters,
              retries,
              tool_timeout,
              reply
            )

          {:error, _} when retries > 0 ->
            Session.append(session, "system", "invalid TOON reply; respond with a valid header")
            step(session, adapter, adapter_opts, tools, iters, retries - 1, tool_timeout)

          {:error, _} ->
            {:error, :max_retries}
        end
    end
  end

  defp handle_reply(session, _adapter, _adapter_opts, _tools, _iters, _retries, _tool_timeout, %{
         "action" => "final",
         "content" => content
       }) do
    Session.append(session, "assistant", content)
    {:ok, content}
  end

  defp handle_reply(session, adapter, adapter_opts, tools, iters, retries, tool_timeout, %{
         "action" => "tool_call",
         "tool" => name,
         "args" => args
       }) do
    result =
      case Map.fetch(tools, name) do
        {:ok, tool} -> ToolRunner.run(tool, args, timeout: tool_timeout)
        :error -> {:error, "unknown tool: #{name}"}
      end

    Session.append(
      session,
      "assistant",
      Toon.encode!(%{"tool_call" => %{"tool" => name, "args" => args}})
    )

    Session.append(session, "observation", inspect(result))
    step(session, adapter, adapter_opts, tools, iters - 1, retries, tool_timeout)
  end

  defp handle_reply(session, adapter, adapter_opts, tools, iters, retries, tool_timeout, _other)
       when retries > 0 do
    Session.append(session, "system", "unknown action; use tool_call or final")
    step(session, adapter, adapter_opts, tools, iters, retries - 1, tool_timeout)
  end

  defp handle_reply(_s, _a, _ao, _t, _i, _r, _tt, _other), do: {:error, :max_retries}

  defp build_prompt(session, tools) do
    tool_rows =
      Enum.map(tools, &%{"name" => &1.tool_name(), "description" => &1.tool_description()})

    """
    Answer with TOON. Action is one of tool_call, final.

    ```toon
    #{Toon.encode!(%{"tools" => tool_rows})}
    ```
    ```toon
    #{Session.to_prompt(session)}
    ```
    """
  end
end
