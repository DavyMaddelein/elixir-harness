defmodule ElixirHarness.UpgradeTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.Showcase.Upgrade
  alias ElixirHarness.Session

  test "hot upgrade flips behavior with the session untouched" do
    mod = Module.concat([UpgradeTestGreeter, "#{System.unique_integer([:positive])}"])
    {:ok, session} = Session.start_link()
    :ok = Session.append(session, "user", "greet me")

    :ok = Upgrade.deploy(mod, 1)
    assert apply(mod, :version, []) == 1
    assert apply(mod, :greet, ["agent"]) =~ "v1"

    :ok = Upgrade.deploy(mod, 2)
    assert apply(mod, :version, []) == 2
    assert apply(mod, :greet, ["agent"]) =~ "v2"

    assert Process.alive?(session)
    assert [%{role: "user"}] = Session.history(session)
  end
end
