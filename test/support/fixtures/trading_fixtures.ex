defmodule TradingLab.TradingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `TradingLab.Trading` context.
  """

  @doc """
  Generate a signal.
  """
  def signal_fixture(attrs \\ %{}) do
    {:ok, signal} =
      attrs
      |> Enum.into(%{
        bsp: 120.5,
        price: 120.5,
        prob: 120.5,
        time: 42,
        type: "some type"
      })
      |> TradingLab.Trading.create_signal()

    signal
  end
end
