defmodule ElixirHarness.CLIAdapter do
  @moduledoc "Behaviour for coding-CLI adapters (OpenCode, Cursor)."
  @callback run(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end

defmodule ElixirHarness.CLI.Runner do
  @moduledoc """
  Port-based subprocess runner with streaming, budgets, and kill.

  Prompt is passed as argv (avoids stdin EOF half-close issues).
  Collects stdout until `:exit_status`.
  `max_ms` / `max_bytes` budgets kill the port.
  """

  @spec run(String.t(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(exe, args, opts \\ []) do
    max_ms = Keyword.get(opts, :max_ms, 30_000)
    max_bytes = Keyword.get(opts, :max_bytes, 1_000_000)
    on_line = Keyword.get(opts, :on_line, nil)
    cd = Keyword.get(opts, :cd, File.cwd!())

    exe_path = System.find_executable(exe) || exe

    port =
      Port.open({:spawn_executable, exe_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        cd: cd
      ])

    collect(port, "", max_ms, max_bytes, on_line)
  end

  defp collect(port, acc, max_ms, max_bytes, on_line) do
    receive do
      {^port, {:data, data}} ->
        acc = acc <> data
        if on_line, do: Enum.each(String.split(data, "\n", trim: true), on_line)

        if byte_size(acc) > max_bytes do
          Port.close(port)
          {:error, :budget_bytes_exceeded}
        else
          collect(port, acc, max_ms, max_bytes, on_line)
        end

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, code}} ->
        {:error, {:exit_status, code, acc}}
    after
      max_ms ->
        Port.close(port)
        {:error, :budget_time_exceeded}
    end
  end
end

defmodule ElixirHarness.CLI.OpenCode do
  @moduledoc "OpenCode CLI adapter. Configurable exe/args; prompt appended to argv."
  @behaviour ElixirHarness.CLIAdapter

  @impl true
  def run(prompt, opts \\ []) do
    exe = Keyword.get(opts, :exe, "opencode")
    base = Keyword.get(opts, :args, ["run"])
    args = if Keyword.get(opts, :append_prompt, true), do: base ++ [prompt], else: base
    ElixirHarness.CLI.Runner.run(exe, args, opts)
  end
end

defmodule ElixirHarness.CLI.Cursor do
  @moduledoc "Cursor CLI adapter with the same Port harness plus budgets."
  @behaviour ElixirHarness.CLIAdapter

  @impl true
  def run(prompt, opts \\ []) do
    exe = Keyword.get(opts, :exe, "cursor")
    base = Keyword.get(opts, :args, ["run"])
    args = if Keyword.get(opts, :append_prompt, true), do: base ++ [prompt], else: base
    ElixirHarness.CLI.Runner.run(exe, args, opts)
  end
end
