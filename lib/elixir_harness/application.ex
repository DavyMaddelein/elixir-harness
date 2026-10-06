defmodule ElixirHarness.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: ElixirHarness.ToolSupervisor},
      {Registry, keys: :unique, name: ElixirHarness.AgentRegistry},
      {DynamicSupervisor, name: ElixirHarness.AgentSupervisor, strategy: :one_for_one},
      %{id: :pg_server, start: {:pg, :start_link, []}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ElixirHarness.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
