defmodule Playcode.Export.PlayChangeListener do
  @moduledoc """
  Relays the `play_changed` notifications Postgres sends when something a play's static
  pages show changes (migration 20261005120000_track_play_content_version):
  - to `"static_site"` as `{:play_changed, play_id}`, so every open export page can flag
    the play at once;
  - to the play's own topic through `PlayContent.notify_changed/1`, so the content editor
    and the play list reload, whoever made the change.

  Postgres sends them on commit, one per play per transaction, and a bulk edit commits one
  transaction per row. Each relay reloads the editor, so notifications are coalesced per
  play: the first one opens a window, and each play changed during it is relayed once when
  it closes.
  """

  # ponytail: a notification sent while the connection is down is lost; the page reads
  # the truth again on mount and after every build.
  # ponytail: a fixed window, so latency stays bounded under continuous writes. A bulk
  # action longer than the window still relays once per window per play; make the window
  # trailing (restart it on each notification) if that proves too chatty.

  use GenServer

  alias Playcode.PlayContent
  alias Postgrex.Notifications

  @window 200

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
    {:ok, MapSet.new()}
  end

  # `pending` is the play ids heard since the window opened. The first one opens it.
  @impl true
  def handle_info({:notification, _conn, _ref, "play_changed", play_id}, pending) do
    if MapSet.size(pending) == 0, do: Process.send_after(self(), :flush, @window)
    {:noreply, MapSet.put(pending, play_id)}
  end

  def handle_info(:flush, pending) do
    for play_id <- pending do
      Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, play_id})
      PlayContent.notify_changed(play_id)
    end

    {:noreply, MapSet.new()}
  end
end
