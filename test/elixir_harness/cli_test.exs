defmodule ElixirHarness.CLITest do
  use ExUnit.Case, async: true

  alias ElixirHarness.CLI.{OpenCode, Cursor}

  test "opencode adapter streams echo output" do
    assert {:ok, "hello\n"} = OpenCode.run("hello", exe: "/bin/echo", args: [])
  end

  test "on_line callback receives lines" do
    parent = self()

    {:ok, _} =
      OpenCode.run("a b",
        exe: "/bin/echo",
        args: [],
        on_line: fn line -> send(parent, {:line, line}) end
      )

    assert_receive {:line, "a b"}
  end

  test "budget time kills hung CLI" do
    assert {:error, :budget_time_exceeded} =
             OpenCode.run("x", exe: "/bin/sleep", args: ["5"], append_prompt: false, max_ms: 50)
  end

  test "nonzero exit returns error" do
    assert {:error, {:exit_status, 1, _}} =
             OpenCode.run("x",
               exe: System.find_executable("false"),
               args: [],
               append_prompt: false
             )
  end

  test "cursor adapter mirrors runner" do
    assert {:ok, "hi\n"} = Cursor.run("hi", exe: "/bin/echo", args: [])
  end
end
