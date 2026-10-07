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
      {:telemetry, "~> 1.0"},
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:lazy_html, ">= 0.0.0", only: :test},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_html, "~> 4.0"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
