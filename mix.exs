defmodule ElixirHarness.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_harness,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {ElixirHarness.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:toon_ex, "~> 1.7"},
      {:telemetry, "~> 1.0"}
    ]
  end
end
