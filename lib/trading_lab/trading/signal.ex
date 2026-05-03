defmodule TradingLab.Trading.Signal do
  use Ecto.Schema
  import Ecto.Changeset

  schema "signals" do
    field :type, :string
    field :price, :float
    field :time, :integer
    field :bsp, :float
    field :prob, :float
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(signal, attrs) do
    signal
    |> cast(attrs, [:type, :price, :time, :bsp, :prob])
    |> validate_required([:type, :price, :time, :bsp, :prob])
  end
end
