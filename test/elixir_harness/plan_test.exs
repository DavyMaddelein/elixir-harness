defmodule ElixirHarness.PlanTest do
  use ExUnit.Case, async: false

  alias ElixirHarness.{Plan, Tools}

  defmodule LinearPlan do
    use ElixirHarness.Plan

    defplan "linear" do
      step(:one, tool: Tools.Math, args: %{"op" => "add", "a" => 1, "b" => 1})
      step(:two, tool: Tools.Math, args: %{"op" => "mul", "a" => 3, "b" => 3}, depends_on: [:one])
    end
  end

  defmodule DiamondPlan do
    use ElixirHarness.Plan

    defplan "diamond" do
      step(:left, tool: Tools.Echo, args: %{"text" => "l"})
      step(:right, tool: Tools.Echo, args: %{"text" => "r"})
      step(:join, tool: Tools.Echo, args: %{"text" => "j"}, depends_on: [:left, :right])
    end
  end

  defmodule FailingPlan do
    use ElixirHarness.Plan

    defmodule Boom do
      use ElixirHarness.Tool
      tool_name("boom")
      tool_description("Raises.")
      tool_schema(%{})
      @impl true
      def run(_), do: raise("boom")
    end

    defplan "failing" do
      step(:good, tool: Tools.Echo, args: %{"text" => "ok"})
      step(:bad, tool: Boom, args: %{}, depends_on: [:good])
      step(:orphan, tool: Tools.Echo, args: %{"text" => "nope"}, depends_on: [:bad])
      step(:free, tool: Tools.Echo, args: %{"text" => "fine"})
    end
  end

  test "linear plan runs in dependency order" do
    assert {:ok, %{one: {:ok, 2}, two: {:ok, 9}}} = Plan.run(LinearPlan.__plans__(), "linear")
  end

  test "diamond plan joins branches" do
    assert {:ok, %{left: {:ok, "l"}, right: {:ok, "r"}, join: {:ok, "j"}}} =
             Plan.run(DiamondPlan.__plans__(), "diamond")
  end

  test "failure halts dependents only" do
    assert {:ok, results} = Plan.run(FailingPlan.__plans__(), "failing")
    assert {:ok, "ok"} = results.good
    assert {:error, _} = results.bad
    assert {:skipped, :bad} = results.orphan
    assert {:ok, "fine"} = results.free
  end

  test "unknown plan is an error" do
    assert {:error, :unknown_plan} = Plan.run(LinearPlan.__plans__(), "nope")
  end

  test "unknown dependency fails compilation" do
    assert_raise ArgumentError, ~r/unknown step/, fn ->
      defmodule BadDepPlan do
        use ElixirHarness.Plan

        defplan "bad" do
          step(:a, tool: Tools.Echo, args: %{}, depends_on: [:ghost])
        end
      end
    end
  end

  test "cycle fails compilation" do
    assert_raise ArgumentError, ~r/cycle/, fn ->
      defmodule CyclePlan do
        use ElixirHarness.Plan

        defplan "cycle" do
          step(:a, tool: Tools.Echo, args: %{}, depends_on: [:b])
          step(:b, tool: Tools.Echo, args: %{}, depends_on: [:a])
        end
      end
    end
  end
end
