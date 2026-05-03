defmodule TradingLabWeb.HudLive do
  use TradingLabWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(TradingLab.PubSub, "market_data")
      Logger.info("HudLive: Connected and subscribed to market_data.")
    end

    # Fetch the history from the DB!
    historical_signals = TradingLab.Trading.list_recent_signals()

    socket = assign(socket,
      lot_size: 1.0,
      prob: 50.0,
      status: "OK",
      signals: historical_signals
    )

    {:ok, socket, layout: {TradingLabWeb.Layouts, :terminal}}
  end

  # This is the "Safety Valve" that prevents the crash!
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
      state: data.state,
      bsp: data.bsp,
      probability: data.probability,
      signal: data.signal
    })

    # --- GET CURRENT MEMORY ---
    current_signals = socket.assigns.signals

    # --- CHECK FOR NEW SIGNAL & SAVE TO DB ---
    updated_signals = if data.signal do
      # 1. Save it to the Black Box
      # Note: Since you are the only user in the lab right now, we can safely
      # assign this to user_id: 1 (the account you just registered).
      {:ok, db_signal} = TradingLab.Trading.create_signal(%{
        user_id: 1,
        type: data.signal,
        price: data.close,
        time: data.time,
        bsp: data.bsp,
        prob: data.probability
      })

      # 2. Update the UI list
      Enum.take([db_signal | current_signals], 50)
    else
      current_signals
    end

    # 2. Update the HUD Header variables AND the signal memory
    socket = assign(socket,
      lot_size: data.lot_size,
      prob: data.probability,
      status: data.status,
      signals: updated_signals # <--- Shoving the updated list back into state
    )

    {:noreply, socket}
  end

  # Catch any other stray messages to prevent crashes
  def handle_info(msg, socket) do
    Logger.debug("HudLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end
end
