defmodule ElixirHarness.ReleaseTrainTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.Poc.ReleaseTrain

  @moduletag timeout: 180_000

  test "clean train ships green end to end" do
    workdir = Path.join(System.tmp_dir!(), "train_test_#{System.unique_integer([:positive])}")
    assert {:ok, %{verdict: :shipped, report: report}} = ReleaseTrain.run(workdir, chaos: false)
    assert report =~ "shards"
    assert File.exists?(Path.join(workdir, "release_snapshot.dets"))
    assert File.exists?(Path.join(workdir, "lib/checkout/rate_limiter.ex"))
    assert File.exists?(Path.join(workdir, "lib/checkout/audit.ex"))
    File.rm_rf!(workdir)
  end
end
