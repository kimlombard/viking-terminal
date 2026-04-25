defmodule TradingLab.EnginePort do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    # FIX 1: Changed :lines to :line
    port = Port.open({:spawn, "./engine/engine"}, [:binary, :exit_status, :line])
    {:ok, %{port: port}}
  end

  # --- Handle Info Group ---
  def handle_info({_port, {:data, {:eol, line}}}, state) do
    if String.starts_with?(line, "candle:") do
      candle_data = parse_candle(line)
      Phoenix.PubSub.broadcast(TradingLab.PubSub, "viking:ticks", {:new_candle, candle_data})
    end

    {:noreply, state}
  end

  # FIX 2: Moved this right below the other handle_info
  def handle_info({_port, {:exit_status, status}}, _state) do
    Logger.error("Viking Engine crashed with status: #{status}")
    {:stop, :engine_crash, %{}}
  end
  # -------------------------

  defp parse_candle(line) do
    ["candle" | rest] = String.split(line, ":")

    # 1. Ensure you add a variable here to catch the state code from your CSV string!
    # (You may need to add it depending on how many fields Odin is printing)
    [t, o, h, l, c, v, ind, stat, sc] = String.split(List.first(rest), ",")

    %{
      time: t,
      open: String.to_float(o),
      high: String.to_float(h),
      low: String.to_float(l),
      close: String.to_float(c),
      volume: String.to_float(v),
      indicator: String.to_float(ind),
      status: stat,

      # 2. Parse the REAL state_code from Odin as an integer
      state_code: String.to_integer(String.trim(sc)),

      y_top: max(String.to_float(o), String.to_float(c)),
      height: abs(String.to_float(o) - String.to_float(c)),
      rel_vol: String.to_float(v) / 100.0
    }
  end
end
