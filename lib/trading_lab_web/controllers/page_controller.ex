defmodule TradingLabWeb.PageController do
  use TradingLabWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
