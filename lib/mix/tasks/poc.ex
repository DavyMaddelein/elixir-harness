defmodule Mix.Tasks.Poc.ReleaseTrain do
  @shortdoc "Run the overnight release-train swarm PoC"
  use Mix.Task

  @impl true
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:elixir_harness)
    chaos? = "--clean" not in args
    workdir = Path.join(System.tmp_dir!(), "release_train_#{System.unique_integer([:positive])}")

    case ElixirHarness.Poc.ReleaseTrain.run(workdir, chaos: chaos?) do
      {:ok, %{verdict: :shipped} = result} ->
        Mix.shell().info("TRAIN SHIPPED: #{result.observations} observations, report below")
        Mix.shell().info(result.report)

      {:error, reason} ->
        Mix.raise("train failed: #{inspect(reason)}")
    end
  end
end
