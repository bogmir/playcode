defmodule Playcode.Repo.Migrations.PlayFormVerseAndProseByShare do
  @moduledoc """
  Question 23: verse and prose is worked out from the text too, from a tenth to under nine
  tenths of the text in verse, Playcode's proposal until the project says where it ends
  (`Play.auto_form/2`). This recomputes `auto_form` once for the plays already stored, with
  the same rule; only the plays whose form changes are written, so only their
  `content_version` moves.
  """
  use Ecto.Migration

  def up, do: recompute(0.9)

  def down, do: recompute(0.1)

  defp recompute(verse_share) do
    execute("""
    UPDATE plays SET auto_form = share.form
    FROM (
      SELECT play_id,
             CASE
               WHEN verse = 0 THEN 'prose'
               WHEN verse < 0.1 * (verse + prose) THEN 'occasional_verse'
               WHEN verse < #{verse_share} * (verse + prose) THEN 'mixed'
               ELSE 'verse'
             END AS form
        FROM (
          SELECT play_id,
                 coalesce(sum(char_length(content)) FILTER (WHERE type = 'verse_line'), 0) AS verse,
                 coalesce(sum(char_length(content)) FILTER (WHERE type = 'prose'), 0) AS prose
            FROM play_elements GROUP BY play_id
        ) AS lengths
    ) AS share
    WHERE share.play_id = plays.id AND plays.auto_form <> share.form
    """)
  end
end
