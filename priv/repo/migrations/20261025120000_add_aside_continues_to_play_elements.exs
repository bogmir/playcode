defmodule Playcode.Repo.Migrations.AddAsideContinuesToPlayElements do
  @moduledoc """
  Whether an element's first aside piece continues the aside before it (the design:
  docs/superpowers/specs/2026-10-25-aside-chains-design.md). Rows already stored get the
  rule the site used until now, a verse continuing when the verse before it in its speech
  is aside, so the site keeps its labels until the corpus is re-imported. Every play
  holding an aside has its content_version moved: its statistics, which now count asides
  rather than pieces, are computed again.
  """
  use Ecto.Migration

  def up do
    alter table(:play_elements) do
      add :aside_continues, :boolean, null: false, default: false
    end

    flush()

    # One pass over the verse lines; a correlated subquery here ran for minutes on dev.
    execute """
    UPDATE play_elements e
    SET aside_continues = true
    FROM (
      SELECT l.id,
             lag(l.is_aside) OVER (
               PARTITION BY coalesce(
                 CASE WHEN p.type = 'line_group' THEN p.parent_id ELSE l.parent_id END,
                 l.division_id
               )
               ORDER BY CASE WHEN p.type = 'line_group' THEN p.position ELSE l.position END,
                        CASE WHEN p.type = 'line_group' THEN l.position ELSE 0 END
             ) AS previous_aside
      FROM play_elements l
      LEFT JOIN play_elements p ON p.id = l.parent_id
      WHERE l.type = 'verse_line'
    ) v
    WHERE e.id = v.id AND e.is_aside AND v.previous_aside
    """

    execute "SELECT touch_play(play_id) FROM (SELECT DISTINCT play_id FROM play_elements WHERE is_aside) a"
  end

  def down do
    alter table(:play_elements) do
      remove :aside_continues
    end
  end
end
