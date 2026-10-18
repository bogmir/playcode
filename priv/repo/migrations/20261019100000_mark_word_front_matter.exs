defmodule Playcode.Repo.Migrations.MarkWordFrontMatter do
  @moduledoc """
  A Word import deleted every paratext of its play before writing the front matter, so a
  paratext typed by hand did not survive it. It now deletes only the front matter it
  wrote, origin "word"; this marks the front matter written before as that, by the kind
  and heading the import gives it, so the next import replaces it instead of adding a
  second one.

  Not reversible: which rows were "manual" before is not recorded. The triggers of
  migration 20261005120000 move the plays' `content_version`.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE play_paratexts SET origin = 'word'
    WHERE origin = 'manual' AND kind = 'nota_edicion_digital' AND heading = 'Front matter'
    """)
  end

  def down, do: :ok
end
