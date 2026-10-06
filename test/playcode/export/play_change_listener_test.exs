defmodule Playcode.Export.PlayChangeListenerTest do
  @moduledoc """
  Postgres's `play_changed` notifications reach the export page's topic and the play's own
  topic. Postgres sends one only when its transaction commits, which the sandbox never
  does, so these tests commit a real play, outside the sandbox, and purge it again.
  """
  # Not async: while the committed play exists, every other test would see it.
  use Playcode.DataCase, async: false

  import Playcode.TestFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Playcode.{Catalogue, PlayContent}
  alias Playcode.Export.SiteBuilder

  test "a committed edit to a play is announced on the static_site topic" do
    SiteBuilder.subscribe()

    Sandbox.unboxed_run(Playcode.Repo, fn ->
      play = play_fixture()

      try do
        {:ok, _} = Catalogue.update_play(play, %{"title" => "Committed"})
        play_id = play.id
        assert_receive {:play_changed, ^play_id}, 5_000
      after
        {:ok, _} = Catalogue.purge_play(play)
      end
    end)
  end

  test "a committed edit reaches the play's own topic, whoever made it" do
    Sandbox.unboxed_run(Playcode.Repo, fn ->
      play = play_fixture()

      try do
        PlayContent.subscribe(play.id)
        # The metadata form's write, which has never broadcast on this topic.
        {:ok, _} = Catalogue.update_play(play, %{"title" => "Committed"})
        play_id = play.id
        assert_receive {:play_content_changed, ^play_id}, 5_000
      after
        {:ok, _} = Catalogue.purge_play(play)
      end
    end)
  end
end
