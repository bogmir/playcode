defmodule Playcode.Repo.Migrations.PlayAutoFormNilWithoutText do
  @moduledoc """
  `auto_form` nil means the play has no verse line and no line of prose: a play without a
  text, read through `Play.has_text?/1`. Such plays held `'prose'` and a `verse_count` of 0.
  """
  use Ecto.Migration

  def up do
    execute "ALTER TABLE plays ALTER COLUMN auto_form DROP NOT NULL, ALTER COLUMN auto_form DROP DEFAULT"

    execute """
    UPDATE plays p SET auto_form = NULL, verse_count = NULL
    WHERE NOT EXISTS (
      SELECT 1 FROM play_elements e
      WHERE e.play_id = p.id AND e.type IN ('verse_line', 'prose')
    )
    """
  end

  def down do
    execute "UPDATE plays SET auto_form = 'prose', verse_count = 0 WHERE auto_form IS NULL"

    execute "ALTER TABLE plays ALTER COLUMN auto_form SET DEFAULT 'prose', ALTER COLUMN auto_form SET NOT NULL"
  end
end
