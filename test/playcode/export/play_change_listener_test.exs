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
  alias Playcode.Export.{PlayChangeListener, SiteBuilder}

  # Regression: init/1 waited for LISTEN, which waits for the connect, so a database
  # that accepts the connection and never answers stopped the app booting after 5 s.
  # The database is a local socket that accepts and never replies.
  test "starts at once though the database never answers" do
    {:ok, server} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, port} = :inet.port(server)

    acceptor =
      spawn(fn ->
        _ = :gen_tcp.accept(server)
        Process.sleep(:infinity)
      end)

    on_exit(fn ->
      Process.exit(acceptor, :kill)
      :gen_tcp.close(server)
    end)

    {micros, result} =
      :timer.tc(fn ->
        PlayChangeListener.start_link(name: nil, hostname: "127.0.0.1", port: port)
      end)

    assert {:ok, listener} = result
    assert micros < 1_000_000

    # Past the API, for a quiet cleanup: killing its connection, the other process it is
    # linked to, takes both down now. Left alone, the connection logs a failed connect.
    Process.unlink(listener)
    {:links, links} = Process.info(listener, :links)
    Enum.each(links -- [self()], &Process.exit(&1, :kill))
  end

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

  # A bulk edit commits one transaction per row, so Postgres sends one notification per
  # row. Each relay makes the content editor reload five lists; a hundred of them queue
  # up ahead of the user's next click. The listener sends each play once per window.
  # No commit needed: the listener is handed the notifications Postgres would send.
  test "notifications for one play within a window are relayed once, on both topics" do
    [bulk, other] = [Ecto.UUID.generate(), Ecto.UUID.generate()]
    SiteBuilder.subscribe()
    PlayContent.subscribe(bulk)
    PlayContent.subscribe(other)

    listener = Process.whereis(Playcode.Export.PlayChangeListener)

    for id <- [bulk, bulk, other, bulk] do
      send(listener, {:notification, self(), make_ref(), "play_changed", id})
    end

    assert_receive {:play_changed, ^bulk}, 1_000
    assert_receive {:play_changed, ^other}, 1_000
    assert_receive {:play_content_changed, ^bulk}, 1_000
    assert_receive {:play_content_changed, ^other}, 1_000

    # Well past the window: no id arrives a second time. Pinned to ours, because the
    # purge in another test's cleanup may relay its own play just after that test ends.
    for id <- [bulk, other] do
      refute_receive {:play_changed, ^id}, 500
      refute_receive {:play_content_changed, ^id}, 100
    end
  end
end
