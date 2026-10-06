defmodule ElixirHarness.ToolTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.Tool
  alias ElixirHarness.Tools.{Math, Echo}

  test "deftool modules expose contract" do
    assert Math.tool_name() == "math"
    assert is_binary(Math.tool_description())
    assert %{"op" => [type: :string, required: true]} = Math.tool_schema()
  end

  test "valid args run" do
    assert {:ok, 3} = Tool.call(Math, %{"op" => "add", "a" => 1, "b" => 2})
    assert {:ok, "hi"} = Tool.call(Echo, %{"text" => "hi"})
  end

  test "invalid args rejected with message" do
    assert {:error, "missing required arg: b"} = Tool.call(Math, %{"op" => "add", "a" => 1})
    assert {:error, "bad type for text" <> _} = Tool.call(Echo, %{"text" => 1})
  end
end
