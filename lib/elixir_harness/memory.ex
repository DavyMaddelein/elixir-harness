defmodule ElixirHarness.Memory.Store do
  @moduledoc "Behaviour for session memory backends."
  @callback new() :: term()
  @callback append(term(), map()) :: :ok
  @callback list(term()) :: [map()]
  @callback clear(term()) :: :ok
end

defmodule ElixirHarness.Memory.ETS do
  @moduledoc "ETS-backed memory: ordered_set owned by the Session process."
  @behaviour ElixirHarness.Memory.Store

  @impl true
  def new do
    :ets.new(:memory, [:ordered_set, :private])
  end

  @impl true
  def append(tid, entry) do
    key = :erlang.unique_integer([:monotonic, :positive])
    :ets.insert(tid, {key, entry})
    :ok
  end

  @impl true
  def list(tid) do
    :ets.tab2list(tid) |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
  end

  @impl true
  def clear(tid) do
    :ets.delete_all_objects(tid)
    :ok
  end
end

defmodule ElixirHarness.Memory.DETS do
  @moduledoc """
  DETS-backed memory: single-file snapshots between ETS (hot) and
  Mnesia (durable). `clear/1` closes the table, removes the file, and
  reopens fresh — the file never lingers.
  """
  @behaviour ElixirHarness.Memory.Store

  @impl true
  def new do
    tag = System.unique_integer([:positive])
    open(Path.join(System.tmp_dir!(), "harness_mem_#{tag}.dets"))
  end

  @doc "Open (or create) the snapshot file at `path`."
  @spec open(Path.t()) :: %{table: atom(), path: Path.t()}
  def open(path) do
    name = :"harness_mem_#{:erlang.phash2(path)}"
    {:ok, ^name} = :dets.open_file(name, file: String.to_charlist(path))
    %{table: name, path: path}
  end

  @doc "Close the table and remove its file."
  @spec close(%{table: atom(), path: Path.t()}) :: :ok
  def close(%{table: table, path: path}) do
    :ok = :dets.close(table)
    _ = File.rm(path)
    :ok
  end

  @impl true
  def append(%{table: table}, entry) do
    key = :erlang.unique_integer([:monotonic, :positive])
    :ok = :dets.insert(table, {key, entry})
    :ok
  end

  @impl true
  def list(%{table: table}) do
    table
    |> :dets.match({:"$1", :"$2"})
    |> Enum.sort_by(&hd/1)
    |> Enum.map(&List.last/1)
  end

  @impl true
  def clear(%{table: table, path: path}) do
    :ok = :dets.close(table)
    _ = File.rm(path)
    {:ok, ^table} = :dets.open_file(table, file: String.to_charlist(path))
    :ok
  end
end

defmodule ElixirHarness.Memory.Mnesia do
  @moduledoc "Mnesia-backed memory: `disc_copies` + transactions, survives restarts."
  @behaviour ElixirHarness.Memory.Store

  require Logger

  @table :harness_memory

  def setup do
    # Schema first, then start: create_schema on a running node fails
    # silently, and disc_copies (unlike ram_copies) requires a schema.
    # The table wait is bounded — a stuck schema lock (e.g. mnesia
    # recovering a kill -9'd peer) triggers one full reset + retry.
    :ok = mnesia_start()

    if table_usable?() do
      :ok
    else
      fresh_setup(2)
    end
  end

  defp fresh_setup(0) do
    raise RuntimeError, "Mnesia setup failed for node #{node()}: schema/table could not be created"
  end

  defp fresh_setup(attempts) do
    reset_schema!()
    :ok = mnesia_start()

    task = Task.async(&do_create_table/0)

    case Task.yield(task, 15_000) do
      {:ok, :ok} ->
        :ok

      {:ok, {:error, reason}} ->
        Task.shutdown(task, :brutal_kill)
        Logger.warning("mnesia setup retry after #{inspect(reason)}")
        fresh_setup(attempts - 1)

      nil ->
        Task.shutdown(task, :brutal_kill)
        fresh_setup(attempts - 1)
    end
  end

  # Verified reset: a half-deleted schema reports already_exists for
  # tables that don't work. Wipe the directory when delete fails.
  defp reset_schema! do
    _ = :mnesia.stop()

    case :mnesia.delete_schema([node()]) do
      :ok ->
        :ok

      {:error, reason} ->
        File.rm_rf!(List.to_string(:mnesia.system_info(:directory)))
        Logger.warning("mnesia wiped directory after #{inspect(reason)}")
        :ok
    end

    case :mnesia.create_schema([node()]) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
    end
  end

  defp do_create_table do
    case :mnesia.create_table(
           @table,
           [attributes: [:key, :entry], type: :ordered_set] ++ copies()
         ) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, _}} -> :ok
      {:aborted, reason} -> {:error, reason}
    end
  end

  defp mnesia_start do
    case :mnesia.start() do
      :ok -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  # Listed is not enough: after a node rename the schema can name a
  # table whose copies live on a dead node name. Usable means a copy
  # on THIS node.
  defp table_usable? do
    @table in :mnesia.system_info(:tables) and
      node() in copies_of(@table)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp copies_of(table) do
    :mnesia.table_info(table, :ram_copies) ++
      :mnesia.table_info(table, :disc_copies) ++
      :mnesia.table_info(table, :disc_only_copies)
  rescue
    _ -> []
  catch
    _, _ -> []
  end

  # disc_copies needs a named node; unnamed dev/test falls back to ram.
  defp copies do
    if node() == :nonode@nohost, do: [ram_copies: [node()]], else: [disc_copies: [node()]]
  end

  @impl true
  def new do
    setup()
    @table
  end

  @impl true
  def append(table, entry) do
    key = :erlang.unique_integer([:monotonic, :positive])

    {:atomic, :ok} =
      :mnesia.transaction(fn -> :mnesia.write({table, key, entry}) end)

    :ok
  end

  @impl true
  def list(table) do
    {:atomic, rows} =
      :mnesia.transaction(fn ->
        :mnesia.foldl(fn {_t, _k, e}, acc -> [e | acc] end, [], table)
      end)

    Enum.reverse(rows)
  end

  @impl true
  def clear(table) do
    {:atomic, :ok} = :mnesia.clear_table(table)
    :ok
  end
end
