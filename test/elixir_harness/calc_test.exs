defmodule ElixirHarness.CalcTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.Tool
  alias ElixirHarness.Tools.Calc

  test "arithmetic evaluates" do
    assert {:ok, 7} = Tool.call(Calc, %{"expr" => "1 + 2 * 3"})
    assert {:ok, 9} = Tool.call(Calc, %{"expr" => "(1 + 2) * 3"})
    assert {:ok, -5} = Tool.call(Calc, %{"expr" => "-5"})
    assert {:ok, 2.5} = Tool.call(Calc, %{"expr" => "10 / 4"})
  end

  test "division by zero is an error, not a crash" do
    assert {:error, _} = Tool.call(Calc, %{"expr" => "1 / 0"})
  end

  test "malicious input is rejected before evaluation" do
    for expr <- [
          ~s{System.cmd("ls", [])},
          ~s{File.read!("/etc/passwd")},
          ":os.cmd('ls')",
          "1 |> IO.inspect()",
          "{1, 2}",
          "[1, 2]",
          "%{a: 1}",
          "x = 1",
          "fn x -> x end",
          "1; System.cmd(\"x\", [])",
          "Enum.map([1], & &1)",
          "__MODULE__",
          "1 + System.cmd(\"x\", [])"
        ] do
      assert {:error, _} = Tool.call(Calc, %{"expr" => expr}), "expected rejection: #{expr}"
    end
  end
end
