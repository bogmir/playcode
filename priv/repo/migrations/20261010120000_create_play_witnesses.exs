defmodule Playcode.Repo.Migrations.CreatePlayWitnesses do
  @moduledoc """
  A play's witnesses (S3): the manuscripts and early printings its text survives in, each
  with the siglum an apparatus cites it by. Spec:
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

  Witnesses show on the play's pages, so the table moves `plays.content_version` like
  every other (migration 20261005120000).
  """
  use Ecto.Migration

  def change do
    create table(:play_witnesses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :siglum, :text
      add :title, :text
      add :normalized_title, :text
      add :attribution, :text
      add :pub_place, :text
      add :publisher, :text
      add :date, :text
      add :format, :text
      add :witness_type, :string
      add :shelfmark, :text
      add :note, :text
      add :position, :integer, null: false, default: 0
      add :origin, :string, null: false, default: "manual"
      add :filemaker_id, :text

      timestamps(type: :utc_datetime)
    end

    create index(:play_witnesses, [:play_id, :position])
    create unique_index(:play_witnesses, [:play_id, :siglum])

    execute "CREATE TRIGGER play_witnesses_touch_play AFTER INSERT OR UPDATE OR DELETE ON play_witnesses FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
            "DROP TRIGGER play_witnesses_touch_play ON play_witnesses"
  end
end
