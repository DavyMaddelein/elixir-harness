defmodule ElixirHarness.Cluster do
  @moduledoc """
  Distribution helpers: boot real `elixir` peer nodes as OS processes,
  sync code paths, join them into the cluster.

  Full BEAM nodes — same code, `:rpc` instead of local calls, `:pg`
  groups spanning machines. No containers, no sidecars.
  """

  @doc "Ensure this node is distributed (shortnames). Idempotent."
  @spec ensure_distributed(atom()) :: {:ok, node()} | {:error, term()}
  def ensure_distributed(name \\ :harness_main) do
    if Node.alive?() do
      {:ok, Node.self()}
    else
      case Node.start(name, :shortnames) do
        {:ok, _} -> {:ok, Node.self()}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Boot a peer `elixir` node named `name`, wait for it to join.
  Returns `{:ok, %{node: node, port: port}}`.
  """
  @spec start_peer(atom(), keyword()) :: {:ok, %{node: node(), port: port()}} | {:error, term()}
  def start_peer(name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    cookie = Node.get_cookie() |> Atom.to_string()
    ebins = app_ebins()

    pa_args = Enum.flat_map(ebins, &["-pa", &1])

    args =
      ["--sname", Atom.to_string(name), "--cookie", cookie] ++
        pa_args ++ ["-e", "Process.sleep(:infinity)"]

    port = Port.open({:spawn_executable, System.find_executable("elixir")}, [:binary, :exit_status, args: args])
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_node(node_name(name), port, deadline)
  end

  @doc "Stop a peer: graceful `:init.stop/0`, or `:kill_9` for the chaos case."
  @spec stop_peer(%{node: node(), port: port()}, :graceful | :kill_9) :: :ok
  def stop_peer(%{node: node, port: port}, mode \\ :graceful) do
    case mode do
      :graceful ->
        :rpc.call(node, :init, :stop, [])

      :kill_9 ->
        {:os_pid, os_pid} = Port.info(port, :os_pid)
        System.cmd("kill", ["-9", to_string(os_pid)])
    end

    Port.close(port)
    :ok
  end

  @doc "Make the app's beams available on `node` and boot the app there."
  @spec ensure_app(node()) :: :ok | {:error, term()}
  def ensure_app(node) do
    with true <- sync_code_paths(node),
         {:ok, _} <- :rpc.call(node, Application, :ensure_all_started, [:elixir_harness]) do
      :ok
    else
      false -> {:error, :code_sync_failed}
      {:badrpc, _} = err -> {:error, err}
      {:error, _} = err -> err
    end
  end

  @doc "Thin wrapper over `:rpc.call`, short-circuiting for the local node."
  @spec rpc(node(), module(), atom(), list()) :: term() | {:badrpc, term()}
  def rpc(node, mod, fun, args) do
    if node == Node.self(), do: apply(mod, fun, args), else: :rpc.call(node, mod, fun, args)
  end

  defp node_name(name), do: :"#{name}@#{host()}"

  defp host do
    {:ok, name} = :inet.gethostname()
    List.to_string(name)
  end

  defp wait_for_node(node, port, deadline) do
    cond do
      Node.connect(node) ->
        {:ok, %{node: node, port: port}}

      System.monotonic_time(:millisecond) > deadline ->
        Port.close(port)
        {:error, :peer_boot_timeout}

      true ->
        Process.sleep(200)
        wait_for_node(node, port, deadline)
    end
  end

  defp sync_code_paths(node) do
    paths = app_ebins() |> Enum.map(&String.to_charlist/1)

    case :rpc.call(node, :code, :add_pathsa, [paths]) do
      {:error, _} -> false
      _ -> true
    end
  end

  defp app_ebins do
    :code.get_path()
    |> Enum.map(&List.to_string/1)
    |> Enum.filter(&String.contains?(&1, "_build"))
  end
end
