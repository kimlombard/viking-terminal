defmodule TradingLab.TradeCopier do
  require Logger

  @brokers [
    "Broker_Alpha_API",
    "Broker_Beta_API",
    "Broker_Gamma_API",
    "Broker_Delta_API",
    "Broker_Epsilon_API"
    # ... scales infinitely
  ]

  @doc """
  Receives a pristine trade signal from the Odin engine and blasts it to all brokers.
  """
  def execute_network_trade(signal) do
    Logger.info("⚡ INCOMING SIGNAL: #{signal.action} #{signal.asset} from #{signal.trader_id}")

    # Spawn a parallel asynchronous task for every single broker
    tasks = Enum.map(@brokers, fn broker ->
      Task.async(fn ->
        # send_to_broker(broker, signal) This is old and slow, which is the function that simulates the actual API call to the broker
        TradingLab.BrokerConnection.execute_trade(broker, signal)
      end)
    end)

    # Wait for all brokers to confirm execution (with a strict 500ms timeout)
    # If a broker takes longer than 500ms, Elixir abandons that specific task
    # so it doesn't hold up the rest of the network.
    results = Task.await_many(tasks, 500)

    Logger.info("✅ NETWORK EXECUTION COMPLETE.")
    results
  end

  @doc """
  Simulates hitting the actual Broker REST API or FIX protocol.
  """
  defp send_to_broker(broker_name, signal) do
    # In reality, this is where HTTPoison or Finch makes the API call.
    # For now, we simulate network latency (10ms to 50ms)
    latency = :rand.uniform(40) + 10
    Process.sleep(latency)

    Logger.debug("[#{broker_name}] Filled #{signal.action} #{signal.asset} in #{latency}ms")

    {:ok, broker_name, signal.action, latency}
  end
end
