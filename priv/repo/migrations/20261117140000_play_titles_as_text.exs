defmodule Playcode.Repo.Migrations.PlayTitlesAsText do
  @moduledoc """
  A play's title and sort title are text, not `varchar(255)`: FileMaker's EMOTHE0797 has a
  title of 405 characters, a baroque title in full.
  """
  use Ecto.Migration

  def change do
    alter table(:plays) do
      modify :title, :text, from: :string
      modify :title_sort, :text, from: :string
    end
  end
end
