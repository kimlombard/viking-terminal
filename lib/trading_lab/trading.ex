defmodule TradingLab.Trading do
  @moduledoc """
  The Trading context.
  """

  import Ecto.Query, warn: false
  alias TradingLab.Repo

  alias TradingLab.Trading.Signal

  @doc """
  Returns the list of signals.

  ## Examples

      iex> list_signals()
      [%Signal{}, ...]

  """
  def list_signals do
    Repo.all(Signal)
  end

  @doc """
  Gets a single signal.

  Raises `Ecto.NoResultsError` if the Signal does not exist.

  ## Examples

      iex> get_signal!(123)
      %Signal{}

      iex> get_signal!(456)
      ** (Ecto.NoResultsError)

  """
  def get_signal!(id), do: Repo.get!(Signal, id)

  @doc """
  Creates a signal.

  ## Examples

      iex> create_signal(%{field: value})
      {:ok, %Signal{}}

      iex> create_signal(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_signal(attrs) do
    %Signal{}
    |> Signal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a signal.

  ## Examples

      iex> update_signal(signal, %{field: new_value})
      {:ok, %Signal{}}

      iex> update_signal(signal, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_signal(%Signal{} = signal, attrs) do
    signal
    |> Signal.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a signal.

  ## Examples

      iex> delete_signal(signal)
      {:ok, %Signal{}}

      iex> delete_signal(signal)
      {:error, %Ecto.Changeset{}}

  """
  def delete_signal(%Signal{} = signal) do
    Repo.delete(signal)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking signal changes.

  ## Examples

      iex> change_signal(signal)
      %Ecto.Changeset{data: %Signal{}}

  """
  def change_signal(%Signal{} = signal, attrs \\ %{}) do
    Signal.changeset(signal, attrs)
  end

  @doc """
  Returns the most recent signals, ordered by time.
  """
  def list_recent_signals(limit \\ 50) do
    Repo.all(
      from s in TradingLab.Trading.Signal,
        order_by: [desc: s.time],
        limit: ^limit
    )
  end
end
