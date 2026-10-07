defmodule Playcode.Repo.Migrations.CreateBibliography do
  @moduledoc """
  S4: the corpus-wide bibliography and each play's links to it. Spec:
  docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  An entry is shared, so an edit to it must move every play that cites it: that is
  `bibliography_entry_changed()`, on the model of `place_changed()` in
  20261005120000_track_play_content_version.exs. Deleting an entry cascades to its links,
  and the cascade fires the links' own trigger.
  """
  use Ecto.Migration

  def change do
    create table(:bibliography_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :pub_type, :string
      add :language, :string

      for column <- ~w(analytic_author analytic_title analytic_editors analytic_translators
                       monogr_author monogr_title monogr_editors monogr_translators
                       original_title edition volume volumes_total issue pages
                       pub_place publisher year_text url url_accessed_on
                       series siglum public_note note)a do
        add column, :text
      end

      add :filemaker_id, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bibliography_entries, [:filemaker_id], where: "filemaker_id IS NOT NULL")

    create table(:play_bibliography, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false

      add :entry_id,
          references(:bibliography_entries, type: :binary_id, on_delete: :delete_all),
          null: false

      add :volume, :text
      add :pages, :text
      add :note, :text
      add :origin, :string, null: false, default: "manual"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:play_bibliography, [:play_id, :entry_id])
    create index(:play_bibliography, [:entry_id])

    execute "CREATE TRIGGER play_bibliography_touch_play AFTER INSERT OR UPDATE OR DELETE ON play_bibliography FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
            "DROP TRIGGER play_bibliography_touch_play ON play_bibliography"

    execute """
            CREATE FUNCTION bibliography_entry_changed() RETURNS trigger AS $$
            BEGIN
              PERFORM touch_play(play_id) FROM play_bibliography WHERE entry_id = NEW.id;
              RETURN NULL;
            END
            $$ LANGUAGE plpgsql
            """,
            "DROP FUNCTION bibliography_entry_changed()"

    # A new entry has no plays yet; a deleted one takes its links with it.
    execute "CREATE TRIGGER bibliography_entries_touch_plays AFTER UPDATE ON bibliography_entries FOR EACH ROW EXECUTE FUNCTION bibliography_entry_changed()",
            "DROP TRIGGER bibliography_entries_touch_plays ON bibliography_entries"
  end
end
