defmodule TradingLab.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TradingLabWeb.Telemetry,
      TradingLab.Repo,
      {DNSCluster, query: Application.get_env(:trading_lab, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TradingLab.PubSub},
      # Start a worker by calling: TradingLab.Worker.start_link(arg)
      # {TradingLab.Worker, arg},
      # Start to serve requests, typically the last entry
      # ADD THIS LINE SO THE ENGINE ACTUALLY BOOTS:
      TradingLab.EnginePort,
      TradingLabWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TradingLab.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TradingLabWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
