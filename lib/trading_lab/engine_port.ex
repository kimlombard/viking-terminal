defmodule TradingLab.EnginePort do
  use GenServer
  require Logger

  @target_bin "./viking" # Ensure this matches your compiled Odin binary name

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # We use :line mode to capture the \n delimited CSV from Odin
    port = Port.open({:spawn, @target_bin}, [:binary, :exit_status, :line])
    Logger.info("Viking Engine Bridge established via Port.")
   {:ok, %{port: port, last_bsp_ema: nil, last_ema: nil}}
  end

  # --- Handle Incoming Data ---
  def handle_info({_port, {:data, {:eol, "candle:" <> raw_csv}}}, state) do
    case parse_csv(raw_csv) do
      {:ok, payload} ->

        # --- 1. MAIN PRICE EMA CALCULATION ---
        alpha = 0.1
        current_close = payload.close
        last_ema = state.last_ema || current_close # Safety net!
        new_ema = (current_close * alpha) + (last_ema * (1.0 - alpha))

        # --- 2. BSP SIGNAL LINE (EMA) CALCULATION ---
        bsp_alpha = 0.15
        current_bsp = payload.bsp
        last_bsp_ema = state.last_bsp_ema || current_bsp # Safety net!
        new_bsp_ema = (current_bsp * bsp_alpha) + (last_bsp_ema * (1.0 - bsp_alpha))

        # --- 3. SIGNAL CALCULATION ---
        signal = cond do
          payload.bsp > 70.0 and payload.probability > 80.0 -> "BUY"
          payload.bsp < -70.0 and payload.probability > 80.0 -> "SELL"
          true -> nil
        end

        # --- 4. BROADCAST ---
        enriched_payload = Map.merge(payload, %{
          signal: signal,
          ema: new_ema,
          bsp_ema: new_bsp_ema
        })
        Phoenix.PubSub.broadcast(TradingLab.PubSub, "market_data", {:new_tick, enriched_payload})

        # --- 5. UPDATE STATE (Save both memories for the next tick) ---
        {:noreply, %{state | last_ema: new_ema, last_bsp_ema: new_bsp_ema}}

      :error ->
        Logger.warning("Viking Port: Failed to parse malformed tick data.")
        {:noreply, state}
    end
  end

  # --- Handle Engine Crashes ---
  def handle_info({_port, {:exit_status, status}}, _state) do
    Logger.error("Viking Engine (Odin) exited with status: #{status}")
    # In a production app, you might want to restart the port here
    {:stop, :engine_crash, %{}}
  end

  # Standard GenServer boilerplate for messages we don't care about
  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private Helpers ---

  defp parse_csv(line) do
    # Expanded Odin Output: time, open, high, low, close, volume, bsp, status, state, lot, prob, poc, vah, val, alma20_high, alma20_low, alma200_high, alma200_low, ghosts
    case String.split(String.trim(line), ",") do
      # This must match the Odin printf EXACTLY column for column
      [t, o, h, l, c, v, ind, stat, sc, lot, prob, poc, vah, val, alma20_high, alma20_low, alma200_high, alma200_low, ghosts, whale] ->
        {:ok, %{
          time: String.to_integer(t),
          open: to_f(o),
          high: to_f(h),
          low: to_f(l),
          close: to_f(c),
          volume: to_f(v),
          bsp: to_f(ind),
          status: stat,
          state: String.to_integer(String.trim(sc)),
          lot_size: to_f(lot),
          probability: to_f(prob),
          poc_price: to_f(poc),
          vah: to_f(vah),
          val: to_f(val),
          alma20_high: to_f(alma20_high),
          alma20_low: to_f(alma20_low),
          alma200_high: to_f(alma200_high),
          alma200_low: to_f(alma200_low),
          ghosts: parse_ghosts(String.trim(ghosts)),
          whale_alert: String.trim(whale)
        }}
      _ ->
        :error
    end
  end

  # Helper to decode the string "18240.5:1|18200.0:0|" into Elixir Maps
  defp parse_ghosts("none"), do: []
  defp parse_ghosts(ghost_str) do
    ghost_str
    |> String.split("|", trim: true)
    |> Enum.map(fn g ->
      [price_str, bull_str] = String.split(g, ":")
      %{price: to_f(price_str), is_bullish: bull_str == "1"}
    end)
  end

  defp to_f(val) do
    case Float.parse(val) do
      {num, _} -> num
      :error -> 0.0
    end
  end
end
