defmodule ElixirHarness.Showcase.ReleaseTrain do
  @moduledoc "Showcase: the overnight release train, chaos included."
  @behaviour ElixirHarness.Showcase

  @impl true
  def name, do: "release-train"

  @impl true
  def description,
    do:
      "Swarm ships rate limiting to a fixture service: kills, failover, hot upgrade — still ships."

  @impl true
  def run do
    workdir =
      Path.join(System.tmp_dir!(), "release_train_show_#{System.unique_integer([:positive])}")

    case ElixirHarness.Poc.ReleaseTrain.run(workdir, chaos: true) do
      {:ok, %{verdict: :shipped, report: report}} ->
        IO.puts("TRAIN SHIPPED. Report:")
        IO.puts(report)
        :ok

      {:error, reason} ->
        raise "train failed: #{inspect(reason)}"
    end
  end
end
