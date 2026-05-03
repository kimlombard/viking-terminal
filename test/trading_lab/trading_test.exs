defmodule TradingLab.TradingTest do
  use TradingLab.DataCase

  alias TradingLab.Trading

  describe "signals" do
    alias TradingLab.Trading.Signal

    import TradingLab.TradingFixtures

    @invalid_attrs %{type: nil, time: nil, price: nil, bsp: nil, prob: nil}

    test "list_signals/0 returns all signals" do
      signal = signal_fixture()
      assert Trading.list_signals() == [signal]
    end

    test "get_signal!/1 returns the signal with given id" do
      signal = signal_fixture()
      assert Trading.get_signal!(signal.id) == signal
    end

    test "create_signal/1 with valid data creates a signal" do
      valid_attrs = %{type: "some type", time: 42, price: 120.5, bsp: 120.5, prob: 120.5}

      assert {:ok, %Signal{} = signal} = Trading.create_signal(valid_attrs)
      assert signal.type == "some type"
      assert signal.time == 42
      assert signal.price == 120.5
      assert signal.bsp == 120.5
      assert signal.prob == 120.5
    end

    test "create_signal/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Trading.create_signal(@invalid_attrs)
    end

    test "update_signal/2 with valid data updates the signal" do
      signal = signal_fixture()
      update_attrs = %{type: "some updated type", time: 43, price: 456.7, bsp: 456.7, prob: 456.7}

      assert {:ok, %Signal{} = signal} = Trading.update_signal(signal, update_attrs)
      assert signal.type == "some updated type"
      assert signal.time == 43
      assert signal.price == 456.7
      assert signal.bsp == 456.7
      assert signal.prob == 456.7
    end

    test "update_signal/2 with invalid data returns error changeset" do
      signal = signal_fixture()
      assert {:error, %Ecto.Changeset{}} = Trading.update_signal(signal, @invalid_attrs)
      assert signal == Trading.get_signal!(signal.id)
    end

    test "delete_signal/1 deletes the signal" do
      signal = signal_fixture()
      assert {:ok, %Signal{}} = Trading.delete_signal(signal)
      assert_raise Ecto.NoResultsError, fn -> Trading.get_signal!(signal.id) end
    end

    test "change_signal/1 returns a signal changeset" do
      signal = signal_fixture()
      assert %Ecto.Changeset{} = Trading.change_signal(signal)
    end
  end
end
