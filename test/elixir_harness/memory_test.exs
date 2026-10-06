defmodule ElixirHarness.MemoryTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.Session

  test "append/list/clear round-trip" do
    {:ok, s} = Session.start_link()
    assert Session.history(s) == []
    :ok = Session.append(s, "user", "hello")
    :ok = Session.append(s, "assistant", "hi")
    assert [%{role: "user"}, %{role: "assistant"}] = Session.history(s)
    :ok = Session.clear(s)
    assert Session.history(s) == []
  end

  test "to_prompt encodes history as TOON" do
    {:ok, s} = Session.start_link()
    :ok = Session.append(s, "user", "hello")
    prompt = Session.to_prompt(s)
    assert prompt =~ "history[1]{content,role}:"
  end

  test "table dies with session" do
    {:ok, s} = Session.start_link()
    :ok = Session.append(s, "user", "x")
    ref = Process.monitor(s)
    GenServer.stop(s)
    assert_receive {:DOWN, ^ref, _, _, _}
  end
end
