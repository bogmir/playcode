defmodule Playcode.Repo.Migrations.AddActorToCharacters do
  @moduledoc """
  The actor who played a character at the first performance, TEI's `castItem/actor`:
  Mr. Betterton as Fainall in The Way of the World, the one play of the corpus with an
  original cast. `characters` has its content trigger already.
  """
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :actor, :text
    end
  end
end
