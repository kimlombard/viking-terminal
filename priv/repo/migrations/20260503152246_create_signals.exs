defmodule TradingLab.Repo.Migrations.CreateSignals do
  use Ecto.Migration

  def change do
    create table(:signals) do
      add :type, :string
      add :price, :float
      add :time, :integer
      add :bsp, :float
      add :prob, :float
      add :user_id, references(:users, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:signals, [:user_id])
  end
end
