defmodule Playcode.Repo.Migrations.RefundicionIsAnAdaptation do
  @moduledoc """
  Question 15, amended 2026-10-26: in English a refundición is only an adaptation, and the
  team's list of kinds files the two together, as FileMaker does. So `refundicion` is no
  longer a kind (`Play.relationship_types/0`), and the import reads it as `adaptacion`.

  No play was one when the kind was dropped; this moves any a curator set in the play form
  since, which the site's `Components.kind/1` would otherwise refuse. Not reversible: an
  adaptation does not record that it was once a refundición.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE plays SET relationship_type = 'adaptacion' WHERE relationship_type = 'refundicion'
    """)
  end

  def down, do: :ok
end
