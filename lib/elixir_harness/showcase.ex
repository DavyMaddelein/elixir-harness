defmodule ElixirHarness.Showcase do
  @moduledoc """
  Runnable showpieces: one module per demoable feature.

  A showcase narrates itself — it prints what it is about to prove,
  proves it, and prints the result. Run one with `mix showcase <name>`
  or list them with `mix showcase`.
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback run() :: :ok

  @spec all() :: [module()]
  def all do
    [
      ElixirHarness.Showcase.Cluster,
      ElixirHarness.Showcase.Dashboard,
      ElixirHarness.Showcase.Calc,
      ElixirHarness.Showcase.Upgrade,
      ElixirHarness.Showcase.Memory,
      ElixirHarness.Showcase.Trace,
      ElixirHarness.Showcase.Chaos,
      ElixirHarness.Showcase.Plan,
      ElixirHarness.Showcase.Isolation,
      ElixirHarness.Showcase.Tiers,
      ElixirHarness.Showcase.Budgets,
      ElixirHarness.Showcase.Backpressure,
      ElixirHarness.Showcase.Registry
    ]
  end

  @spec find(String.t()) :: {:ok, module()} | :error
  def find(name) do
    case Enum.find(all(), &(&1.name() == name)) do
      nil -> :error
      mod -> {:ok, mod}
    end
  end
end
