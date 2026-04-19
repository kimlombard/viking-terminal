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
    ~H"""
    <div class="p-4 bg-slate-900 min-h-screen text-white">
      <h1 class="text-2xl font-mono mb-4 text-green-400">Viking Terminal // Live Feed</h1>

      <div id="chart-container"
           phx-hook="ChartHook"
           phx-update="ignore"
           class="rounded-lg overflow-hidden border border-slate-700">
      </div>
    </div>
    """
  end

  # 2. This function catches the messages coming FROM Odin
  def handle_info({_port, {:data, msg}}, socket) do
    # Format: "candle:timestamp,open,high,low,close"
    data = String.trim(msg) |> String.replace("candle:", "") |> String.split(",")

    case data do
      [t, o, h, l, c, v] ->
        tick_data = %{
          time: String.to_integer(t),
          open: String.to_float(o),
          high: String.to_float(h),
          low: String.to_float(l),
          close: String.to_float(c),
          value: String.to_float(v) # Lightweight Charts calls volume 'value'
        }
        {:noreply, push_event(socket, "new_tick", tick_data)}

      _ ->
        {:noreply, socket}
    end
  end
end
