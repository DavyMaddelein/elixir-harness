defmodule ElixirHarness.MemoryDetsTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.Memory.DETS
  alias ElixirHarness.Session

  test "store round-trip" do
    handle = DETS.new()
    :ok = DETS.append(handle, %{role: "user", content: "hi"})
    assert [%{content: "hi"}] = DETS.list(handle)
    :ok = DETS.close(handle)
  end

  test "clear removes the file and stays usable" do
    handle = DETS.new()
    :ok = DETS.append(handle, %{role: "user", content: "hi"})
    path = handle.path
    assert File.exists?(path)
    :ok = DETS.clear(handle)
    assert DETS.list(handle) == []
    :ok = DETS.append(handle, %{role: "user", content: "again"})
    assert [%{content: "again"}] = DETS.list(handle)
    :ok = DETS.close(handle)
  end

  test "close removes the file" do
    handle = DETS.new()
    path = handle.path
    assert File.exists?(path)
    :ok = DETS.close(handle)
    refute File.exists?(path)
  end

  test "snapshot survives session death, restores into a new one" do
    path =
      Path.join(System.tmp_dir!(), "harness_snapshot_#{System.unique_integer([:positive])}.dets")

    {:ok, s1} = Session.start_link()
    :ok = Session.append(s1, "user", "remember this")
    :ok = Session.snapshot(s1, path)
    GenServer.stop(s1)

    {:ok, s2} = Session.start_link()
    assert Session.history(s2) == []
    :ok = Session.restore(s2, path)
    assert [%{role: "user", content: "remember this"}] = Session.history(s2)
    File.rm(path)
  end
end
