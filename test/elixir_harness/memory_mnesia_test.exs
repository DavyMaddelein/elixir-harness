defmodule ElixirHarness.MemoryMnesiaTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.Memory.Mnesia

  setup do
    # Hermetic slate: distribution renames and kill -9'd peers leave
    # ghost schema entries behind that fail unpredictably. Wipe first.
    _ = :mnesia.stop()
    _ = :mnesia.delete_schema([node()])
    for dir <- Path.wildcard("Mnesia.*"), do: File.rm_rf!(dir)

    table = Mnesia.new()
    Mnesia.clear(table)
    {:ok, table: table}
  end

  test "round-trip persists in the table", %{table: t} do
    :ok = Mnesia.append(t, %{role: "user", content: "remember this"})
    assert [%{content: "remember this"}] = Mnesia.list(t)
  end

  test "aborted transaction leaves no partial write", %{table: t} do
    {:aborted, _} =
      :mnesia.transaction(fn ->
        :mnesia.write({t, -1, %{x: 1}})
        :mnesia.abort(:nope)
      end)

    assert Mnesia.list(t) == []
  end

  test "fresh setup works on a distributed node (schema-before-start)" do
    {:ok, _} =
      ElixirHarness.Cluster.ensure_distributed(
        :"mnesia_dist_#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> ElixirHarness.PeerCluster.undistribute() end)

    _ = :mnesia.stop()
    _ = :mnesia.delete_schema([node()])
    assert :harness_memory = Mnesia.new()
    assert :ok = Mnesia.append(:harness_memory, %{role: "user", content: "durable"})
    assert [%{content: "durable"}] = Mnesia.list(:harness_memory)
    assert node() in :mnesia.system_info(:running_db_nodes)

    # Leave no schema behind for sibling tests.
    _ = :mnesia.stop()
    _ = :mnesia.delete_schema([node()])
  end
end
