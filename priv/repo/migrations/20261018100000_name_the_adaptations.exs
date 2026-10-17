defmodule Playcode.Repo.Migrations.NameTheAdaptations do
  @moduledoc """
  Question 15, decided 2026-10-16: each kind by its own name, as the files call them. The
  import read only `<title type="traduccion">`, and `relationship_type` is never written
  by a re-import, so the plays already stored keep what the first import and FileMaker's
  index gave them: 10 adaptations stored as originals (EMOTHE0653, *The Shy Courtier*, as
  a translation), and 3 versions (question 40) as originals.

  FileMaker's index heads a family with its first editor, so it put Ford's *'Tis Pity*
  (EMOTHE0283) and its translations under Maeterlinck's adaptation of it, Guarini's
  *Il pastor fido* (0006) and its translations under Calderón's auto (0165), and
  *Las mocedades del Cid* (0141) under *Le Cid*, which adapts it. Those families are
  corrected here, and `FilemakerSync` keeps them so.

  Codes are matched on their prefix, since a stored code carries the title
  (`EMOTHE0030_LeMenteur`); a database without a play matches nothing. Not reversible:
  what each row held before is not recorded. The triggers of migration 20261005120000
  move the plays' `content_version`, so Generate refreshes them.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE plays SET relationship_type = 'adaptacion'
    WHERE split_part(code, '_', 1) IN ('EMOTHE0030', 'EMOTHE0049', 'EMOTHE0090', 'EMOTHE0120',
      'EMOTHE0121', 'EMOTHE0192', 'EMOTHE0298', 'EMOTHE0317', 'EMOTHE0653', 'EMOTHE0687')
      AND relationship_type IS DISTINCT FROM 'adaptacion'
    """)

    # Question 40 asks what a version is; until then the word the files give is kept.
    execute("""
    UPDATE plays SET relationship_type = 'version'
    WHERE split_part(code, '_', 1) IN ('EMOTHE0503', 'EMOTHE0715', 'EMOTHE0750')
      AND relationship_type IS NULL
    """)

    # Ford's and Guarini's plays are the originals of their families: Annabella and the
    # two translations of 'Tis Pity, El pastor fido and the two of Il pastor fido hang
    # from them.
    execute("""
    UPDATE plays SET parent_play_id = NULL
    WHERE split_part(code, '_', 1) IN ('EMOTHE0283', 'EMOTHE0006')
    """)

    for {play, original} <- [
          {"EMOTHE0317", "EMOTHE0283"},
          {"EMOTHE0284", "EMOTHE0283"},
          {"EMOTHE0404", "EMOTHE0283"},
          {"EMOTHE0298", "EMOTHE0006"},
          {"EMOTHE0210", "EMOTHE0006"},
          {"EMOTHE0286", "EMOTHE0006"}
        ] do
      execute("""
      UPDATE plays p SET parent_play_id = o.id FROM plays o
      WHERE split_part(p.code, '_', 1) = '#{play}' AND split_part(o.code, '_', 1) = '#{original}'
        AND o.deleted_at IS NULL
      """)
    end

    # Las mocedades del Cid (c. 1618) is the original; Corneille's Le Cid (1637) adapts it,
    # so it names no original title either (its file said "Le Cid").
    execute("""
    UPDATE plays SET relationship_type = NULL, parent_play_id = NULL,
      original_title = CASE WHEN original_title = 'Le Cid' THEN NULL ELSE original_title END
    WHERE split_part(code, '_', 1) = 'EMOTHE0141'
    """)
  end

  def down, do: :ok
end
