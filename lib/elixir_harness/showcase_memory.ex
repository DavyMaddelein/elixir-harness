defmodule ElixirHarness.Showcase.Memory do
  @moduledoc "Showcase: snapshot a session to one file, kill it, bring it back."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.Session

  @impl true
  def name, do: "memory"

  @impl true
  def description, do: "DETS snapshot: kill a session, restore its history into a new one."

  @impl true
  def run do
    path = Path.join(System.tmp_dir!(), "harness_demo_snapshot.dets")
    {:ok, s1} = Session.start_link()
    :ok = Session.append(s1, "user", "remember this")
    :ok = Session.snapshot(s1, path)
    IO.puts("snapshotted to #{path}, killing #{inspect(s1)}")
    GenServer.stop(s1)

    {:ok, s2} = Session.start_link()
    :ok = Session.restore(s2, path)
    IO.inspect(Session.history(s2), label: "restored into #{inspect(s2)}")
    File.rm(path)
    :ok
  end
end
