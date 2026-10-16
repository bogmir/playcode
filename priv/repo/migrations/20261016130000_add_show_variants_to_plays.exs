defmodule Playcode.Repo.Migrations.AddShowVariantsToPlays do
  @moduledoc """
  "Show variant readings": whether readers see a play's textual variants. Hamlet's
  apparatus is unfinished (question 2 of docs/stakeholder/preguntas.html), so its are
  hidden until its editor has finished. The TEI import never writes it, and the file never
  carries it.
  """
  use Ecto.Migration

  def up do
    alter table(:plays) do
      add :show_variants, :boolean, null: false, default: true
    end

    execute "UPDATE plays SET show_variants = false WHERE code = 'EMOTHE0010' OR code LIKE 'EMOTHE0010\\_%'"
  end

  def down do
    alter table(:plays) do
      remove :show_variants
    end
  end
end
