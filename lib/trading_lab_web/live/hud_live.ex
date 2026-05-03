defmodule TradingLabWeb.HudLive do
  use TradingLabWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to the SAME topic used in EnginePort
      Phoenix.PubSub.subscribe(TradingLab.PubSub, "market_data")
      Logger.info("HudLive: Connected and subscribed to market_data.")
    end

    # Explicitly set the layout to your terminal layout
    {:ok, socket, layout: {TradingLabWeb.Layouts, :terminal}}
  end

  # This is the "Safety Valve" that prevents the crash!
  def handle_info({:new_tick, data}, socket) do
    # Push the data to the JavaScript 'TradingTerminal' hook[cite: 1, 2]
    {:noreply, push_event(socket, "new_tick", data)}
  end

  # Catch any other stray messages to prevent crashes
  def handle_info(msg, socket) do
    Logger.debug("HudLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end
end
