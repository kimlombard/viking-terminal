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
    {:ok, %{port: port}}
  end

  # --- Handle Incoming Data ---
  # --- Handle Incoming Data ---
  def handle_info({_port, {:data, {:eol, "candle:" <> raw_csv}}}, state) do
    case parse_csv(raw_csv) do
      {:ok, payload} ->
        # 1. Determine if we have a Viking Signal
        signal = cond do
          payload.bsp > 70.0 and payload.probability > 80.0 -> "BUY"
          payload.bsp < -70.0 and payload.probability > 80.0 -> "SELL"
          true -> nil
        end

        # 2. Add the signal to the payload map
        enriched_payload = Map.put(payload, :signal, signal)

        # 3. Broadcast the enriched payload
        Phoenix.PubSub.broadcast(TradingLab.PubSub, "market_data", {:new_tick, enriched_payload})

      :error ->
        Logger.warning("Viking Port: Failed to parse malformed tick data.")
    end

    {:noreply, state}
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
    # Odin Output: time, open, high, low, close, volume, indicator, status, state_code, lot, prob
    case String.split(line, ",") do
      [t, o, h, l, c, v, ind, stat, sc, lot, prob] ->
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
          probability: to_f(prob)
        }}
      _ ->
        :error
    end
  end

  defp to_f(val) do
    case Float.parse(val) do
      {num, _} -> num
      :error -> 0.0
    end
  end
end
