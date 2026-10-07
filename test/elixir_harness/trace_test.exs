defmodule ElixirHarness.TraceTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.Trace

  test "one loop turn is fully observable with zero instrumentation" do
    scripted = fn ->
      {:ok, s} = ElixirHarness.Session.start_link()
      :ok = ElixirHarness.Session.append(s, "user", "hi")

      ElixirHarness.Loop.run(s, Trace.MockAdapter, [ElixirHarness.Tools.Math],
        adapter_opts: [calls: self()]
      )
    end

    {{:ok, "traced"}, calls} = Trace.trace(scripted)
    names = Trace.summarize(calls)
    assert "Loop.run/4" in names
    assert "Session.append/3" in names
    assert "Toon.decode/1" in names
  end
end
