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
  # This is the "Safety Valve" that prevents the crash!
  def handle_info({:new_tick, data}, socket) do
    # 1. Push event to JS Chart
    socket = push_event(socket, "new_tick", %{
      time: data.time,
      open: data.open,
      high: data.high,
      low: data.low,
      close: data.close,
      state: data.state,          # Using data.state from parse_csv
      bsp: data.bsp,              # Using data.bsp from parse_csv
      probability: data.probability,
      signal: data.signal
    })

    # 2. Update the HUD Header variables
    socket = assign(socket,
      lot_size: data.lot_size,
      prob: data.probability,     # Already a float from parse_csv!
      status: data.status
    )

    {:noreply, socket}
  end

  # Catch any other stray messages to prevent crashes
  def handle_info(msg, socket) do
    Logger.debug("HudLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end
end
