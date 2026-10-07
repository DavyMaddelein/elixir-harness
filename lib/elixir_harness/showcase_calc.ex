defmodule ElixirHarness.Showcase.Calc do
  @moduledoc "Showcase: model-supplied formulas, safely evaluated."
  @behaviour ElixirHarness.Showcase

  alias ElixirHarness.{ToolRunner, Tools.Calc}

  @impl true
  def name, do: "calc"

  @impl true
  def description,
    do: "Safe formula evaluator: AST-whitelisted arithmetic, hostile input rejected."

  @impl true
  def run do
    IO.puts("model says: (1 + 2) * 3")
    IO.inspect(ToolRunner.run(Calc, %{"expr" => "(1 + 2) * 3"}), label: "trusted math, evaluated")

    IO.puts("model says: System.cmd(\"rm -rf /\", [])")

    IO.inspect(ToolRunner.run(Calc, %{"expr" => ~s{System.cmd("rm -rf /", [])}}),
      label: "rejected before eval"
    )

    :ok
  end
end
