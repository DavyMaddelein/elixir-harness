defmodule ElixirHarness.ToolRunner do
  @moduledoc """
  Isolated tool execution under `Task.Supervisor`.

  A crashing or hung tool returns `{:error, reason}` — it never takes
  down the session. Emits Logger + `:telemetry` per call.
  """
  require Logger

  @spec run(module(), map(), keyword()) :: {:ok, term()} | {:error, term()}
  def run(tool, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    start = System.monotonic_time(:millisecond)

    task =
      Task.Supervisor.async_nolink(ElixirHarness.ToolSupervisor, fn ->
        ElixirHarness.Tool.call(tool, args)
      end)

    result =
      case Task.yield(task, timeout) do
        {:ok, {:ok, value}} ->
          {:ok, value}

        {:ok, {:error, _} = err} ->
          err

        {:exit, reason} ->
          {:error, {:exit, reason}}

        nil ->
          Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end

    ms = System.monotonic_time(:millisecond) - start

    :telemetry.execute([:elixir_harness, :tool, :run], %{duration_ms: ms}, %{
      tool: tool.tool_name(),
      ok: match?({:ok, _}, result)
    })

    unless match?({:ok, _}, result) do
      Logger.warning("tool failed", tool: tool.tool_name(), result: inspect(result))
    end

    result
  end
end
