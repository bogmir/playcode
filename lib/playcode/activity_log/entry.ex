defmodule Playcode.ActivityLog.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @actions ~w(create update delete import export role_change)
  @resource_types ~w(play character division element editor source editorial_note user place play_place bibliography_entry play_bibliography)

  schema "activity_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}

    belongs_to :user, Playcode.Accounts.User
    belongs_to :play, Playcode.Catalogue.Play

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :user_id,
      :play_id,
      :action,
      :resource_type,
      :resource_id,
      :changes,
      :metadata
    ])
    |> validate_required([:action, :resource_type])
    |> validate_inclusion(:action, @actions)
    |> validate_inclusion(:resource_type, @resource_types)
  end

  def actions, do: @actions
  def resource_types, do: @resource_types
end
