defmodule TradingLabWeb.HudLive do
  use TradingLabWeb, :live_view

  @layout {TradingLabWeb.Layouts, :terminal}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(TradingLab.PubSub, "viking:ticks")

    {:ok, assign(socket, candles: [], lot_size: 0.0, target_prob: 0.0)}
  end

  # Change 1: Add the %{} map syntax to explicitly match the data structure
  def handle_info({:new_candle, %{} = data}, socket) do
    # Trap 1: This will print the raw map to your terminal
    IO.inspect(data, label: "LIVEVIEW CAUGHT CANDLE")

    lot_size = Map.get(data, :lot_size, 0.0)
    target_prob = Map.get(data, :target_prob, 0.0)

    # Instead of storing candles in an Elixir array, we push the event
    # directly to the "new_candle" listener in our Javascript ChartHook!
    {:noreply,
      socket
      |> assign(lot_size: lot_size, target_prob: target_prob)
      |> push_event("new_candle", data)
    }
  end
end
