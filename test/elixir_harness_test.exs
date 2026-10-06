defmodule ElixirHarnessTest do
  use ExUnit.Case
  doctest ElixirHarness

  test "greets the world" do
    assert ElixirHarness.hello() == :world
  end
end
