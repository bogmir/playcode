defmodule Playcode.Export.PlayChangeListener do
  @moduledoc """
  Relays the `play_changed` notifications Postgres sends when something a play's static
  pages show changes (migration 20261005120000_track_play_content_version):
  - to `"static_site"` as `{:play_changed, play_id}`, so every open export page can flag
    the play at once;
  - to the play's own topic through `PlayContent.notify_changed/1`, so the content editor
    and the play list reload, whoever made the change.

  Postgres sends them on commit, one per play per transaction.
  """

  # ponytail: a notification sent while the connection is down is lost; the page reads
  # the truth again on mount and after every build.

  use GenServer

  alias Playcode.PlayContent
  alias Postgrex.Notifications

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    # Its own connection, outside the pool: LISTEN holds it for good. It connects in the
    # background and reconnects after a drop, so the app starts without the database,
    # as the Repo does.
    {:ok, conn} =
      Playcode.Repo.config()
      |> Keyword.merge(sync_connect: false, auto_reconnect: true)
      |> Notifications.start_link()

    {_ok_or_eventually, _ref} = Notifications.listen(conn, "play_changed")
    {:ok, conn}
  end

  @impl true
  def handle_info({:notification, _conn, _ref, "play_changed", play_id}, conn) do
    Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, play_id})
    PlayContent.notify_changed(play_id)
    {:noreply, conn}
  end
end
