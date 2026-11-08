defmodule Playcode.Repo.Migrations.LineNumberAsText do
  use Ecto.Migration

  # A verse's number as the file writes it ("3-4" in Hamlet), not its leading digits. The
  # integers stored so far become their plain text; play_elements has its content trigger.
  def change do
    alter table(:play_elements) do
      modify :line_number, :text, from: :integer
    end
  end
end
