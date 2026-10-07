defmodule ElixirHarness.PeerCluster do
  @moduledoc """
  Test helper: boot `:peer` nodes into the cluster. No Docker, no CI
  services — just the local epmd daemon (`epmd -daemon`; it usually
  starts itself on first use).

  Why not OS processes (like `Cluster.start_peer/2`)? Peers are cheaper
  (~100ms), supervised by the test process, and die with it — ideal for
  ExUnit. Two deliberate differences: the origin must be distributed
  (`ensure_distributed/0`), and Elixir is *not* `:elixir.start/0`'d on the
  peer (that boots `:user`, which fights the peer's stdio connection).
  Beams + `Application.ensure_all_started/1` are enough.
  """

  @doc "Ensure the test VM is distributed. Idempotent."
  @spec ensure_distributed() :: {:ok, node()} | {:error, term()}
  def ensure_distributed do
    ElixirHarness.Cluster.ensure_distributed(
      :"harness_test_#{System.unique_integer([:positive])}"
    )
  end

  @doc "Boot a peer node with our code paths and the app started."
  @spec start_peer(keyword()) :: {:ok, %{node: node(), server: pid()}} | {:error, term()}
  def start_peer(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    name = :"harness_peer_#{System.unique_integer([:positive])}"
    paths = origin_paths()
    pa = Enum.flat_map(paths, &[~c"-pa", String.to_charlist(&1)])

    with {:ok, server, node} <-
           :peer.start_link(%{name: name, connection: :standard_io, args: pa, wait_boot: timeout}),
         true <- Node.connect(node),
         :ok <- sync_paths(node, paths),
         {:ok, _} <- :rpc.call(node, Application, :ensure_all_started, [:elixir_harness]) do
      {:ok, %{node: node, server: server}}
    else
      false -> {:error, :connect_failed}
      {:error, _} = err -> err
      {:badrpc, _} = err -> {:error, err}
    end
  end

  @doc "Stop a peer. Supervised by OTP — also dies with the test process."
  @spec stop_peer(%{server: pid()}) :: :ok
  def stop_peer(%{server: server}) do
    :peer.stop(server)
    :ok
  end

  defp origin_paths do
    :code.get_path() |> Enum.map(&List.to_string/1)
  end

  defp sync_paths(node, paths) do
    case :rpc.call(node, :code, :add_pathsa, [Enum.map(paths, &String.to_charlist/1)]) do
      {:error, _} -> {:error, :code_sync_failed}
      _ -> :ok
    end
  end
end
