defmodule ElixirHarness.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_harness,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia, :runtime_tools, :inets],
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
      # Dashboard-only. The harness runtime (lib/elixir_harness, except
      # dashboard.ex) never touches these; Dashboard.boot/1 raises
      # without them.
      {:phoenix, "~> 1.8", optional: true},
      {:phoenix_live_view, "~> 1.1", optional: true},
      {:phoenix_pubsub, "~> 2.1", optional: true},
      {:phoenix_html, "~> 4.0", optional: true},
      {:bandit, "~> 1.0", optional: true}
    ]
  end
end
