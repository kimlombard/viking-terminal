defmodule TradingLabWeb.ChartLive do
  use TradingLabWeb, :live_view

  def mount(_params, _session, socket) do
    # Only start the engine if we are connected to the websocket
    if connected?(socket) do
      # 1. Start the Odin engine as a Port
      # This assumes your 'engine' binary is in the project root
      Port.open({:spawn, "./engine"}, [:binary, :exit_status])
    end

    {:ok, assign(socket, :current_price, 100.0)}
  end

  def render(assigns) do
    # Default status to "OK" if it hasn't loaded yet
    assigns = assign_new(assigns, :viking_status, fn -> "OK" end)

    ~H"""
    <div class="p-6 bg-slate-900 min-h-screen text-white font-mono">

      <div class="flex justify-between items-center mb-6">
        <div>
          <h1 class="text-3xl font-bold text-slate-100">VIKING TERMINAL</h1>
          <p class="text-sm text-slate-400">Odin Engine: v1.0.0-alpha</p>
        </div>

        <div class={[
          "px-6 py-2 rounded-full border-2 font-bold tracking-widest transition-all duration-300",
          @viking_status == "OK" && "bg-green-900/50 border-green-500 text-green-400 shadow-[0_0_15px_rgba(34,197,94,0.5)]",
          @viking_status == "VIOLATION" && "bg-red-900/50 border-red-500 text-red-400 shadow-[0_0_25px_rgba(239,68,68,0.8)] animate-pulse"
        ]}>
          STATUS: <%= @viking_status %>
        </div>
      </div>

      <div class={[
          "rounded-lg overflow-hidden border-2 transition-all duration-500",
          @viking_status == "OK" && "border-slate-700",
          @viking_status == "VIOLATION" && "border-red-500/50"
        ]}>
        <div id="chart-container"
             phx-hook="ChartHook"
             phx-update="ignore"
             class="w-full h-[600px]">
        </div>
      </div>

    </div>
    """
  end

  # 2. This function catches the messages coming FROM Odin
  def handle_info({_port, {:data, msg}}, socket) do
    # Format: "candle:timestamp,open,high,low,close"
    data = String.trim(msg) |> String.replace("candle:", "") |> String.split(",")

    case data do
      [t, o, h, l, c, v, sma, status] ->
        # If status is "VIOLATION", we could trigger a UI alert here!
        tick_data = %{
          time: String.to_integer(t),
          open: String.to_float(o),
          high: String.to_float(h),
          low: String.to_float(l),
          close: String.to_float(c),
          value: String.to_float(v), # Lightweight Charts calls volume 'value'
          sma: String.to_float(sma)
        }

        # Update the socket with the current status for the UI
        socket = assign(socket, :viking_status, status)

        {:noreply, push_event(socket, "new_tick", tick_data)}

      _ ->
        {:noreply, socket}
    end
  end
end

defmodule VikingWeb.EngineConsumer do
  @doc "Parses the candle:time,open,high,low,close,vol,indicator,status format"
  def parse_line(line) do
    ["candle" | data] = String.split(line, ":")
    [t, o, h, l, c, v, ind, stat] = String.split(List.first(data), ",")

    %{
      time: t,
      open: String.to_float(o),
      high: String.to_float(h),
      low: String.to_float(l),
      close: String.to_float(c),
      volume: String.to_float(v),
      indicator: String.to_float(ind),
      status: stat
    }
  end
end
