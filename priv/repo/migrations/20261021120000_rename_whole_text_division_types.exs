defmodule Playcode.Repo.Migrations.RenameWholeTextDivisionTypes do
  @moduledoc """
  Question 41: the project writes a whole text's type in English, `poem` for the *Arte
  nuevo* and its verse translations and `prose` for the French one, not `poema` and
  `discurso`.
  """
  use Ecto.Migration

  def up do
    execute "UPDATE play_divisions SET type = 'poem' WHERE type = 'poema'"
    execute "UPDATE play_divisions SET type = 'prose' WHERE type = 'discurso'"
  end

  def down do
    execute "UPDATE play_divisions SET type = 'poema' WHERE type = 'poem'"
    execute "UPDATE play_divisions SET type = 'discurso' WHERE type = 'prose'"
  end
end
