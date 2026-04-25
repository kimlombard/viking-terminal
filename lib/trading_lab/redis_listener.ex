defmodule TradingLab.RedisListener do
  use GenServer
  require Logger

  # Start the listener when your Phoenix server boots
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Logger.info("🎧 Booting Redis Pub/Sub Listener...")

    # Connect to your local (or managed Upstash) Redis server
    # We use Redix.PubSub to specifically listen for broadcasts
    {:ok, pubsub_conn} = Redix.PubSub.start_link("redis://localhost:6379")

    # Subscribe to the exact channel Odin will be publishing to
    Redix.PubSub.subscribe(pubsub_conn, "trade_signals", self())

    {:ok, %{conn: pubsub_conn}}
  end

  # This callback fires the millisecond Odin pushes a message to Redis
  @impl true
  def handle_info({:redix_pubsub, _pubsub, _ref, :message, %{channel: "trade_signals", payload: payload}}, state) do
    Logger.debug("⚡ SIGNAL INTERCEPTED FROM ODIN: #{payload}")

    # Decode the JSON payload from Odin
    case Jason.decode(payload) do
      {:ok, signal} ->
        # Send it straight into your execution network!
        TradingLab.TradeCopier.execute_network_trade(signal)

      {:error, _} ->
        Logger.error("Failed to decode Odin signal payload.")
    end

    {:noreply, state}
  end

  # Catch-all for standard subscription confirmations
  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
