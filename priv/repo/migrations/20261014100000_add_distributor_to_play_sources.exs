defmodule Playcode.Repo.Migrations.AddDistributorToPlaySources do
  @moduledoc """
  Where the digital text of a source came from, TEI's `sourceDesc/bibl/distributor`
  ("Procedencia" on emothe.uv.es): Canon 60, Gallica, Internet Shakespeare Editions…,
  in 153 of the production files. `play_sources` has its content trigger already.
  """
  use Ecto.Migration

  def change do
    alter table(:play_sources) do
      add :distributor, :text
    end
  end
end
