defmodule Playcode.Repo.Migrations.AddBackToPlayParatexts do
  @moduledoc """
  A paratext after the text (TEI's `<back>`): an epilogue, a licence to print, a colophon.
  `content` may be empty: 12 head titles and 4 notes on the digital edition are a
  heading alone. `play_paratexts` has its `play_row_changed()` trigger; a column needs
  nothing.
  """
  use Ecto.Migration

  def change do
    alter table(:play_paratexts) do
      add :back, :boolean, default: false, null: false
      modify :content, :text, null: true, from: {:text, null: false}
    end
  end
end
