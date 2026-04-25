defmodule TradingLab.BrokerConnection do
  use GenServer
  require Logger

  # --- CLIENT API ---

  @doc """
  Starts a dedicated, persistent process for a single broker.
  """
  def start_link(broker_name) do
    GenServer.start_link(__MODULE__, broker_name, name: via_tuple(broker_name))
  end

  @doc """
  Fires a trade through the already-open connection.
  """
  def execute_trade(broker_name, signal) do
    GenServer.cast(via_tuple(broker_name), {:fire_order, signal})
  end

  # Creates a unique registry name so we can easily route trades
  defp via_tuple(broker_name), do: {:global, {:broker, broker_name}}


  # --- SERVER CALLBACKS ---

  @impl true
  def init(broker_name) do
    Logger.info("🟢 Booting Persistent Connection: #{broker_name}")

    # 1. Perform the slow SSL handshake/Login HERE, before trading starts.
    # We simulate establishing a FIX Protocol or WebSocket connection.
    connection_state = %{
      name: broker_name,
      status: :connected,
      session_token: "auth_#{:rand.uniform(999999)}"
    }

    {:ok, connection_state}
  end

  @impl true
  def handle_cast({:fire_order, signal}, state) do
    # 2. The trade arrives! The connection is already warm.
    # We just push the bytes down the open TCP pipe.

    start_time = System.monotonic_time(:microsecond)

    # Simulate the instant execution via the open pipe
    # (In production, this is where the FIX/API payload is sent)
    Process.sleep(2)

    end_time = System.monotonic_time(:microsecond)
    latency_us = end_time - start_time

    Logger.debug("⚡ [#{state.name}] Executed #{signal.action} #{signal.asset} in #{latency_us} MICROSECONDS.")

    {:noreply, state}
  end
end
