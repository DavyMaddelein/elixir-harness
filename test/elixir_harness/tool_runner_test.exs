defmodule ElixirHarness.ToolRunnerTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.ToolRunner
  alias ElixirHarness.Tools.Math

  defmodule Sleeper do
    use ElixirHarness.Tool
    tool_name("sleeper")
    tool_description("Sleeps.")
    tool_schema(%{})
    @impl true
    def run(_),
      do:
        (
          Process.sleep(500)
          {:ok, :woke}
        )
  end

  defmodule Crasher do
    use ElixirHarness.Tool
    tool_name("crasher")
    tool_description("Raises.")
    tool_schema(%{})
    @impl true
    def run(_), do: raise("boom")
  end

  test "success passes through" do
    assert {:ok, 3} = ToolRunner.run(Math, %{"op" => "add", "a" => 1, "b" => 2})
  end

  test "timeout kills hung tool" do
    assert {:error, :timeout} = ToolRunner.run(Sleeper, %{}, timeout: 50)
  end

  test "crash returns error and supervisor survives" do
    assert {:error, _} = ToolRunner.run(Crasher, %{})
    # supervisor + app still alive: next run works
    assert {:ok, 3} = ToolRunner.run(Math, %{"op" => "add", "a" => 1, "b" => 2})
  end
end
