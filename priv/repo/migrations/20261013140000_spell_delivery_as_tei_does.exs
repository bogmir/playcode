defmodule Playcode.Repo.Migrations.SpellDeliveryAsTeiDoes do
  @moduledoc """
  24 source files spell TEI's stage type "delivery" as "delivery_", and the importer kept
  it, on stage directions (`stage_type`, 79 in dev) and on the stages inside lines and
  paragraphs (`<stage type="delivery_">` in `content`, 418 elements). The importer reads
  it as "delivery" now; this rewrites what is already stored, so the export, and the
  content editor's list of kinds, give TEI's word.

  Not reversible: which rows were spelled the other way is not recorded. The triggers of
  migration 20261005120000 move the plays' `content_version`.
  """
  use Ecto.Migration

  def up do
    execute("UPDATE play_elements SET stage_type = 'delivery' WHERE stage_type = 'delivery_'")

    execute("""
    UPDATE play_elements
    SET content = replace(content, '<stage type="delivery_">', '<stage type="delivery">')
    WHERE content LIKE '%<stage type="delivery\\_">%'
    """)
  end

  def down, do: :ok
end
