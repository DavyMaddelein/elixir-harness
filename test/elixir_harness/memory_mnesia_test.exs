defmodule ElixirHarness.MemoryMnesiaTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.Memory.Mnesia

  setup do
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
end
