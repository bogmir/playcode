defmodule Playcode.Repo.Migrations.AddVariantsToPlayNotes do
  @moduledoc """
  An entry of the critical apparatus, a TEI `<app>`, is a play_notes row of type
  "variante": its `type` as `variant_type`, its `to` as `range_end`, its `<lem>` and
  `<rdg>`s as `readings`. Its own note is the body, which it may lack. The play_notes
  trigger covers the new columns.
  """
  use Ecto.Migration

  def change do
    alter table(:play_notes) do
      add :variant_type, :string
      add :range_end, :string
      add :readings, :jsonb, null: false, default: fragment("'[]'::jsonb")
      modify :body, :text, null: true, from: {:text, null: false}
    end
  end
end
