defmodule ElixirHarness.LoopTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.{Loop, Session, Toon}
  alias ElixirHarness.Tools.Math

  # Adapter serving scripted replies through an Agent.
  defmodule QueueAdapter do
    @behaviour ElixirHarness.CLIAdapter
    @impl true
    def run(_prompt, opts) do
      agent = Keyword.fetch!(opts, :agent)

      Agent.get_and_update(agent, fn
        [h | t] -> {{:ok, h}, t}
        [] -> {{:error, :empty_script}, []}
      end)
    end
  end

  defp start_script(replies) do
    {:ok, a} = Agent.start_link(fn -> replies end)
    [adapter_opts: [agent: a]]
  end

  test "loop runs tool then returns final" do
    {:ok, s} = Session.start_link()
    :ok = Session.append(s, "user", "add 1 and 2")

    tool_call =
      Toon.encode!(%{
        "action" => "tool_call",
        "tool" => "math",
        "args" => %{"op" => "add", "a" => 1, "b" => 2}
      })

    final = Toon.encode!(%{"action" => "final", "content" => "3"})
    opts = start_script([tool_call, final])

    assert {:ok, "3"} = Loop.run(s, QueueAdapter, [Math], opts)
    history = Session.history(s)
    assert Enum.any?(history, &(&1.role == "observation"))
  end

  test "truncated TOON retries instead of executing" do
    {:ok, s} = Session.start_link()
    :ok = Session.append(s, "user", "hi")

    bad = "users[2]{id,name}:\n  1,Ada\n"
    final = Toon.encode!(%{"action" => "final", "content" => "done"})
    opts = start_script([bad, final])

    assert {:ok, "done"} = Loop.run(s, QueueAdapter, [Math], opts)
  end

  test "unknown tool is observed, loop continues" do
    {:ok, s} = Session.start_link()
    :ok = Session.append(s, "user", "hi")

    call = Toon.encode!(%{"action" => "tool_call", "tool" => "nope", "args" => %{}})
    final = Toon.encode!(%{"action" => "final", "content" => "ok"})
    opts = start_script([call, final])

    assert {:ok, "ok"} = Loop.run(s, QueueAdapter, [Math], opts)
  end
end
