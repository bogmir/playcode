defmodule Playcode.Repo.Migrations.MoveEditionPagesToLinks do
  @moduledoc """
  A modern edition's pages and volume say where a play sits in it, so they belong to the
  play's link, not to the edition every play citing it shares. FileMaker's edition record
  (T04.1 `EdiMod_Pag`) held the pages of the play it was made for, and the S4 import put
  them on the shared entry: *Chief Pre-Shakespearean Dramas* carried *Everyman*'s
  423–68, which *Gorboduc*'s file then wrote as the book's own. This gives them to the
  links that have none of their own and takes them off the entry, so each play's file
  says where it sits (`citedRange`) and the edition gives no pages. One entry in dev.

  Not reversible: which link received the pages is not recorded. The triggers of
  migration 20261005120000 move the plays' `content_version`, so their pages and files
  are rebuilt.
  """
  use Ecto.Migration

  def up do
    for field <- ["pages", "volume"] do
      execute("""
      UPDATE play_bibliography AS l SET #{field} = e.#{field}
      FROM bibliography_entries AS e
      WHERE l.entry_id = e.id AND e.kind = 'modern_edition'
        AND coalesce(btrim(e.#{field}), '') <> '' AND coalesce(btrim(l.#{field}), '') = ''
      """)

      execute("""
      UPDATE bibliography_entries SET #{field} = NULL
      WHERE kind = 'modern_edition' AND coalesce(btrim(#{field}), '') <> ''
      """)
    end
  end

  def down, do: :ok
end
