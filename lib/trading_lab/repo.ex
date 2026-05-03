defmodule TradingLab.Repo do
  use Ecto.Repo,
    otp_app: :trading_lab,
    adapter: Ecto.Adapters.Postgres
end
