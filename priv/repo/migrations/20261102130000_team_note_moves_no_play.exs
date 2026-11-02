defmodule Playcode.Repo.Migrations.TeamNoteMovesNoPlay do
  @moduledoc """
  The team note (question 58) is printed nowhere, so an edit to it moves no
  `content_version`: no static page rebuilt unchanged, no open play page reloaded. The two
  plays triggers of 20261005120000_track_play_content_version, recreated with `team_note`
  among the columns their WHEN clause leaves out.
  """
  use Ecto.Migration

  @bookkeeping "content_version,content_txid,updated_at"

  def up, do: recreate("#{@bookkeeping},team_note")
  def down, do: recreate(@bookkeeping)

  defp recreate(ignored) do
    changed = """
    to_jsonb(OLD) - '{#{ignored}}'::text[]
      IS DISTINCT FROM to_jsonb(NEW) - '{#{ignored}}'::text[]
    """

    execute "DROP TRIGGER plays_bump ON plays"
    execute "DROP TRIGGER plays_touch_relatives ON plays"

    execute """
    CREATE TRIGGER plays_bump BEFORE UPDATE ON plays
      FOR EACH ROW WHEN (#{changed}) EXECUTE FUNCTION play_changed()
    """

    execute """
    CREATE TRIGGER plays_touch_relatives AFTER UPDATE ON plays
      FOR EACH ROW WHEN (#{changed}) EXECUTE FUNCTION play_changed()
    """
  end
end
