defmodule TradingLabWeb.HudLive do
  use TradingLabWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to the SAME topic used in EnginePort
      Phoenix.PubSub.subscribe(TradingLab.PubSub, "market_data")
      Logger.info("HudLive: Connected and subscribed to market_data.")
    end

    # Initialize the HUD memory so the page renders safely
    socket = assign(socket, lot_size: 1.0, prob: 50.0, status: "OK")

    # Explicitly set the layout to your terminal layout
    {:ok, socket, layout: {TradingLabWeb.Layouts, :terminal}}
  end

  # This is the "Safety Valve" that prevents the crash!
  def handle_info({:new_tick, data}, socket) do
    # 1. Update the Elixir state for the HTML Header
    socket = assign(socket,
      lot_size: data.lot_size,
      prob: data.probability,
      status: data.status
    )

    # 2. Push the payload to JavaScript for the Charts
    {:noreply, push_event(socket, "new_tick", data)}
  end

  # Catch any other stray messages to prevent crashes
  def handle_info(msg, socket) do
    Logger.debug("HudLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end
end
