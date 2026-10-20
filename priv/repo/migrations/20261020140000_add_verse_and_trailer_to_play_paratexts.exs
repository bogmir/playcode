defmodule Playcode.Repo.Migrations.AddVerseAndTrailerToPlayParatexts do
  @moduledoc """
  A paratext in verse, TEI's `<lg>`s of `<l>`s, its `content` a line to a line and a blank
  line between stanzas, and a paratext's closing formula, TEI's `<trailer>`: the
  commendatory sonnet and "FIN" after Les Contents and Los contentos (question 30).
  `play_paratexts` has its `play_row_changed()` trigger; a column needs nothing.
  """
  use Ecto.Migration

  def change do
    alter table(:play_paratexts) do
      add :verse, :boolean, default: false, null: false
      add :trailer, :text
    end
  end
end
