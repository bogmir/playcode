defmodule Playcode.ActivityLogTest do
  @moduledoc """
  The log's own rules: what it accepts, and how list_entries/1 filters, orders and
  pages. That admin actions write entries is asserted where the actions happen,
  in the LiveView tests.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.ActivityLog

  test "an entry records who did what to which play, and either may be absent" do
    user = user_fixture()
    play = play_fixture()

    {:ok, _} =
      ActivityLog.log(%{
        user_id: user.id,
        play_id: play.id,
        action: "create",
        resource_type: "play"
      })

    {:ok, _} = ActivityLog.log(%{action: "import", resource_type: "play", play_id: play.id})
    {:ok, _} = ActivityLog.log(%{user_id: user.id, action: "role_change", resource_type: "user"})

    entries =
      Enum.map(
        ActivityLog.list_entries(),
        &{&1.action, &1.user && &1.user.email, &1.play && &1.play.title}
      )

    assert Enum.sort(entries) == [
             {"create", user.email, play.title},
             {"import", nil, play.title},
             {"role_change", user.email, nil}
           ]
  end

  test "an entry needs a known action and resource type" do
    for attrs <- [
          %{},
          %{action: "invalid", resource_type: "play"},
          %{action: "create", resource_type: "invalid"}
        ] do
      assert {:error, changeset} = ActivityLog.log(attrs)
      assert Map.take(errors_on(changeset), [:action, :resource_type]) != %{}
    end
  end

  # log!/1 is called in the middle of admin actions; a logging failure must not take
  # the action down with it. A user id that does not exist violates the foreign key,
  # which raises from the database rather than returning a changeset error.
  test "log!/1 swallows a database error instead of raising" do
    refute ActivityLog.log!(%{
             user_id: Ecto.UUID.generate(),
             action: "create",
             resource_type: "play"
           })
  end

  describe "listing" do
    setup do
      [user_a, user_b] = [user_fixture(), user_fixture()]
      [play_a, play_b] = [play_fixture(), play_fixture()]

      log = fn attrs ->
        {:ok, entry} = ActivityLog.log(attrs)
        entry
      end

      entries = %{
        a:
          log.(%{user_id: user_a.id, play_id: play_a.id, action: "create", resource_type: "play"}),
        b:
          log.(%{user_id: user_b.id, play_id: play_b.id, action: "delete", resource_type: "play"}),
        c:
          log.(%{
            user_id: user_a.id,
            play_id: play_b.id,
            action: "create",
            resource_type: "character"
          })
      }

      %{entries: entries, user_a: user_a, play_b: play_b}
    end

    test "each filter narrows the list, and the count agrees",
         %{entries: e, user_a: user_a, play_b: play_b} do
      today = Date.to_iso8601(Date.utc_today())
      tomorrow = Date.to_iso8601(Date.add(Date.utc_today(), 1))

      for {filter, expected} <- [
            {[user_id: user_a.id], [e.a, e.c]},
            {[play_id: play_b.id], [e.b, e.c]},
            {[action: "create"], [e.a, e.c]},
            {[resource_type: "character"], [e.c]},
            {[from: today, to: today], [e.a, e.b, e.c]},
            {[from: tomorrow], []},
            {[action: "create", play_id: play_b.id], [e.c]}
          ] do
        ids = filter |> ActivityLog.list_entries() |> Enum.map(& &1.id) |> Enum.sort()

        assert ids == expected |> Enum.map(& &1.id) |> Enum.sort(), inspect(filter)
        assert ActivityLog.count_entries(filter) == length(expected), inspect(filter)
      end
    end

    # Entries logged within the same second, as a burst of admin actions is, still
    # list newest first.
    test "the most recent entry comes first", %{entries: e} do
      burst =
        for _ <- 1..10 do
          {:ok, entry} = ActivityLog.log(%{action: "export", resource_type: "play"})
          entry.id
        end

      assert Enum.map(ActivityLog.list_entries(), & &1.id) ==
               Enum.reverse([e.a.id, e.b.id, e.c.id | burst])
    end

    test "a `to` date includes the last fraction of that day", %{entries: e} do
      # No public function logs at a chosen instant, so set the timestamp directly.
      import Ecto.Query
      alias Playcode.{ActivityLog.Entry, Repo}

      today = Date.utc_today()
      {:ok, last_moment} = DateTime.new(today, ~T[23:59:59.500000], "Etc/UTC")
      Repo.update_all(from(x in Entry, where: x.id == ^e.a.id), set: [inserted_at: last_moment])

      assert e.a.id in Enum.map(ActivityLog.list_entries(to: Date.to_iso8601(today)), & &1.id)
    end

    test "pages", %{entries: _} do
      assert length(ActivityLog.list_entries(page: 1, per_page: 2)) == 2
      assert length(ActivityLog.list_entries(page: 2, per_page: 2)) == 1
    end
  end
end
