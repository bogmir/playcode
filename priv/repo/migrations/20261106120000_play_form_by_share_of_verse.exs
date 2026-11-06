defmodule Playcode.Repo.Migrations.PlayFormByShareOfVerse do
  @moduledoc """
  Question 23 (answered 2026-10-19 and 2026-10-21): a play's form is worked out from the
  share of its text in verse, by length, every verse line counted whether numbered or
  not. `is_verse` said only whether the play had a numbered verse, so 17 plays whose
  verse lines carry no number showed as prose, and 33 prose plays with a song showed as
  verse. `auto_form` replaces it: "prose", "occasional_verse" (under a tenth in verse) or
  "verse"; "mixed" stays a researcher's choice. `Catalogue.update_form_and_verse_count/1`
  keeps it from now on; this computes it once for the plays already stored, with the
  same rule.

  The four plays the project named as verse and prose on 2026-10-21 (Sophonisba, La
  finzione veritiera, La novella della vecchia, The Shoemaker's Holiday) are set so by
  hand, unless a researcher already chose. Codes are matched on their prefix, so a
  database without them matches nothing. The plays triggers move every play's
  `content_version`, so Generate rebuilds them all.
  """
  use Ecto.Migration

  def up do
    alter table(:plays) do
      add :auto_form, :string, null: false, default: "prose"
    end

    execute("""
    UPDATE plays SET auto_form = CASE
        WHEN share.verse = 0 THEN 'prose'
        WHEN share.verse < 0.1 * (share.verse + share.prose) THEN 'occasional_verse'
        ELSE 'verse'
      END
    FROM (
      SELECT play_id,
             coalesce(sum(char_length(content)) FILTER (WHERE type = 'verse_line'), 0) AS verse,
             coalesce(sum(char_length(content)) FILTER (WHERE type = 'prose'), 0) AS prose
        FROM play_elements GROUP BY play_id
    ) AS share
    WHERE share.play_id = plays.id
    """)

    execute("""
    UPDATE plays SET form = 'mixed'
    WHERE split_part(code, '_', 1) IN ('EMOTHE0271', 'EMOTHE0045', 'EMOTHE0302', 'EMOTHE0262')
      AND form IS NULL
    """)

    alter table(:plays) do
      remove :is_verse
    end
  end

  # The four plays' form is not set back: what each held before is not recorded.
  def down do
    alter table(:plays) do
      add :is_verse, :boolean, default: true
    end

    execute("UPDATE plays SET is_verse = coalesce(verse_count, 0) > 0")

    alter table(:plays) do
      remove :auto_form
    end
  end
end
