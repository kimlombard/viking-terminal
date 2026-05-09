defmodule TradingLabWeb.HudLive do
  use TradingLabWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(TradingLab.PubSub, "market_data")
      Logger.info("HudLive: Connected and subscribed to market_data.")
    end

    # 1. Grab the first user to ensure the ID is valid
    user = List.first(TradingLab.Accounts.list_users())

    # Fetch the history from the DB!
    historical_signals = TradingLab.Trading.list_recent_signals()

    socket = assign(socket,
      user: user, # Store user in state
      lot_size: 1.0,
      prob: 50.0,
      status: "OK",
      signals: historical_signals,

      # --- NEW: INITIAL BROKER DEFAULTS ---
      balance: 100000.0,
      pnl: 0.0,
      position: 0
    )

    {:ok, socket, layout: {TradingLabWeb.Layouts, :terminal}}
  end

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
      bsp_ema: data.bsp_ema,
      probability: data.probability,
      signal: data.signal,
      ema: data.ema,
      poc: data.poc_price,
      vah: data.vah,
      val: data.val,
      alma20_high: data.alma20_high,
      alma20_low: data.alma20_low,
      alma200_high: data.alma200_high,
      alma200_low: data.alma200_low,
      ghosts: data.ghosts,
      whale_alert: data.whale_alert,

      # --- NEW BROKER DATA ---
      position: data.position,
      pnl: data.pnl,
      balance: data.balance
    })

    # --- GET CURRENT MEMORY ---
    current_signals = socket.assigns.signals

    # --- CHECK FOR NEW SIGNAL & SAVE TO DB ---
    updated_signals = if data.signal do
      # 1. Determine the signal to add
      new_signal = if socket.assigns.user do
        case TradingLab.Trading.create_signal(%{
            user_id: socket.assigns.user.id,
            type: data.signal,
            price: data.close,
            time: data.time,
            bsp: data.bsp,
            prob: data.probability
          }) do
            {:ok, saved_signal} ->
              saved_signal # Return JUST the struct
            {:error, changeset} ->
              Logger.error("VIKING DB FAILURE: #{inspect(changeset.errors)}")
              nil
        end
      else
        %TradingLab.Trading.Signal{type: data.signal, price: data.close}
      end

      # 2. Prepend only if the signal exists, then take 50
      if new_signal, do: Enum.take([new_signal | current_signals], 50), else: current_signals
    else
      current_signals
    end

    # 2. Update the HUD Header variables AND the signal memory
    socket = assign(socket,
      lot_size: data.lot_size,
      prob: data.probability,
      status: data.status,
      signals: updated_signals, # <--- Shoving the updated list back into state

      # --- NEW BROKER DATA ---
      position: data.position,
      pnl: data.pnl,
      balance: data.balance
    )

    {:noreply, socket}
  end

  # Catch any other stray messages to prevent crashes
  def handle_info(msg, socket) do
    Logger.debug("HudLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end
end
