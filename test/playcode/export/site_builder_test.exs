defmodule Playcode.Export.SiteBuilderTest do
  @moduledoc """
  The one process that writes and ships the admin's static site. Driven through its
  public functions and read back from the files it writes and the broadcasts it sends.
  """
  # Not async: the builder runs in the app's tree, so its tasks reach the database only
  # in the shared sandbox, and it writes the one site directory the admin page also uses.
  use Playcode.DataCase, async: false

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Catalogue
  alias Playcode.Export.{SiteBuilder, StaticSite}

  setup do
    File.rm_rf!(StaticSite.output_dir())

    on_exit(fn ->
      await_idle_builder()
      File.rm_rf!(StaticSite.output_dir())
    end)

    SiteBuilder.subscribe()
    :ok
  end

  defp in_site, do: StaticSite.list_exported_codes(StaticSite.output_dir())

  defp in_search do
    {"plays", "all", plays} = load_js!(StaticSite.output_dir(), "search/plays.js")
    Enum.map(plays, & &1["code"])
  end

  # Every broadcast up to and including `last`, in the order they arrived, each as
  # {kind, job or request}.
  defp events_until(last, seen \\ []) do
    event =
      receive do
        {:site_builder, kind, job} -> {kind, job}
        {:site_builder, kind, job, _} -> {kind, job}
      after
        10_000 -> flunk("no #{inspect(last)} after #{inspect(Enum.reverse(seen))}")
      end

    if event == last, do: Enum.reverse([event | seen]), else: events_until(last, [event | seen])
  end

  # Not a race, in every test that queues: a build loads from the database and writes
  # files, milliseconds, while the next call follows within microseconds, and the
  # builder marks itself busy before it replies to the first.

  test "a request during a build waits its turn, then lands" do
    a = play_fixture()
    b = play_fixture()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(b.id, [])

    events = events_until({:done, {:batch, [{:add, b.id}]}})
    assert {:queued, {:add, b.id}} in events
    assert {:done, {:batch, [{:add, a.id}]}} in events
    assert in_site() == Enum.sort([a.code, b.code])
    assert Enum.sort(in_search()) == Enum.sort([a.code, b.code])
  end

  test "the adds and removes that queue during a build run as one batch" do
    [a, b, c] = for _ <- 1..3, do: play_fixture()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(b.id, [])
    assert :queued = SiteBuilder.add(c.id, [])
    assert :queued = SiteBuilder.remove(a.code, [])

    batch = {:batch, [{:add, b.id}, {:add, c.id}, {:remove, a.code}]}
    assert {:started, batch} in events_until({:done, batch})
    assert in_site() == Enum.sort([b.code, c.code])
    assert Enum.sort(in_search()) == Enum.sort([b.code, c.code])
  end

  test "a batch announces its pages before its search index" do
    a = play_fixture()
    assert :started = SiteBuilder.add(a.id, [])

    batch = {:batch, [{:add, a.id}]}

    assert events_until({:done, batch}) == [
             {:started, batch},
             {:published, batch},
             {:done, batch}
           ]
  end

  # The site is current, so this Generate is incremental and keeps the add because it
  # writes only what changed; the next test covers the full build.
  test "an incremental generate queued behind an add keeps the add" do
    [a, b, _never_published] = for _ <- 1..3, do: play_fixture(%{"is_complete" => true})
    {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [a.code])

    assert :started = SiteBuilder.add(b.id, [])
    assert :queued = SiteBuilder.generate(play_codes: [a.code])
    events_until({:done, :generate})

    assert in_site() == Enum.sort([a.code, b.code])
  end

  test "a full generate queued behind an add rebuilds the site as it stands when it runs" do
    [a, b, _never_published] = for _ <- 1..3, do: play_fixture(%{"is_complete" => true})
    {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [a.code])

    assert :started = SiteBuilder.add(b.id, [])
    # The admin page used to send the plays it showed when clicked, before b landed;
    # rebuilding from that list would delete b. A new version makes the site changed,
    # so this Generate rebuilds every play instead of refreshing.
    assert :queued = SiteBuilder.generate(version: "2.0", play_codes: [a.code])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 2}}}, 10_000

    assert in_site() == Enum.sort([a.code, b.code])
  end

  test "a play that no longer exists is skipped and the rest of its batch lands" do
    a = play_fixture()
    b = play_fixture()
    missing = Ecto.UUID.generate()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(missing, [])
    assert :queued = SiteBuilder.add(b.id, [])

    batch = {:batch, [{:add, missing}, {:add, b.id}]}
    assert_receive {:site_builder, :done, ^batch, {:ok, %{skipped: [^missing]}}}, 10_000
    assert in_site() == Enum.sort([a.code, b.code])
  end

  @tag :capture_log
  test "a batch that crashes is reported, and the queue carries on" do
    # Play codes are not validated, and one that is not a plain name cannot be a folder.
    bad = play_fixture(%{"code" => "bad/code"})
    good = play_fixture()

    assert :started = SiteBuilder.add(bad.id, [])
    assert :queued = SiteBuilder.add(good.id, [])

    events = events_until({:done, {:batch, [{:add, good.id}]}})
    assert {:failed, {:batch, [{:add, bad.id}]}} in events
    assert in_site() == [good.code]
    assert SiteBuilder.status() == %{job: nil, queue: []}
  end

  test "status names the running job and the requests waiting behind it" do
    a = play_fixture()
    b = play_fixture()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(b.id, [])
    assert SiteBuilder.status() == %{job: {:batch, [{:add, a.id}]}, queue: [{:add, b.id}]}

    events_until({:done, {:batch, [{:add, b.id}]}})
    assert SiteBuilder.status() == %{job: nil, queue: []}
  end

  # A deploy pushes the whole directory, so it waits for the build before it.
  test "a deploy asked for twice during a build is queued once and runs after it" do
    a = play_fixture()
    assert :started = SiteBuilder.add(a.id, [])

    # Invalid on purpose: Deployer rejects a repository without "/" before it pushes
    # anything, so this test can never reach GitHub.
    assert :queued = SiteBuilder.deploy("not a repo")
    assert :queued = SiteBuilder.deploy("not a repo")
    assert SiteBuilder.status().queue == [:deploy]

    events = events_until({:done, :deploy})
    assert Enum.count(events, &(&1 == {:started, :deploy})) == 1

    assert Enum.find_index(events, &(&1 == {:done, {:batch, [{:add, a.id}]}})) <
             Enum.find_index(events, &(&1 == {:started, :deploy}))
  end

  # Regression: a deploy to a corrected repository was dropped as a duplicate, so the
  # first, mistyped, one ran.
  test "a request asked for again while waiting runs with the options of the latest ask" do
    a = play_fixture()
    assert :started = SiteBuilder.add(a.id, [])

    # Both invalid on purpose (no "/"): the error names the repository that ran.
    assert :queued = SiteBuilder.deploy("old repo")
    assert :queued = SiteBuilder.deploy("new repo")

    assert_receive {:site_builder, :done, :deploy, {:error, reason}}, 10_000
    assert reason =~ "new repo"
    refute reason =~ "old repo"
  end

  # Regression: an unexpected message crashed the builder, which restarted idle while
  # its job ran on. A {nil, _} while idle even matched the task's reply, whose ref is nil
  # then, and crashed it in demonitor(nil).
  test "a stray message neither stops the builder nor reports anything" do
    builder = Process.whereis(SiteBuilder)
    send(builder, :stray)
    send(builder, {nil, :x})

    # A call is answered only after the messages sent before it.
    assert SiteBuilder.status() == %{job: nil, queue: []}
    assert Process.whereis(SiteBuilder) == builder
    refute_receive {:site_builder, _, _, _}
  end

  # Rewriting a play deletes its folder first, so a file planted there says whether the
  # play was written again. File times have one-second resolution, too coarse here.
  defp sentinel(play), do: Path.join([StaticSite.output_dir(), "plays", play.code, "sentinel"])
  defp plant(play), do: File.write!(sentinel(play), "")
  defp rewritten?(play), do: not File.exists?(sentinel(play))

  defp complete_plays(n), do: for(_ <- 1..n, do: play_fixture(%{"is_complete" => true}))

  test "Generate rewrites only the plays that changed since the last build" do
    [a, b] = complete_plays(2)
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 2}}}, 10_000
    Enum.each([a, b], &plant/1)

    {:ok, _} = Catalogue.update_play(a, %{"title" => "Revised"})
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 1, skipped: []}}}, 10_000

    assert rewritten?(a)
    refute rewritten?(b)
    assert read!(StaticSite.output_dir(), "plays/#{a.code}/index.html") =~ "Revised"
  end

  test "Generate with nothing changed writes nothing" do
    [a] = complete_plays(1)
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 1}}}, 10_000
    plant(a)

    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 0, skipped: []}}}, 10_000
    refute rewritten?(a)
  end

  test "Generate takes out the plays archived or no longer complete since the last build" do
    [archived, draft, kept] = complete_plays(3)
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 3}}}, 10_000

    {:ok, _} = Catalogue.delete_play(archived)
    {:ok, _} = Catalogue.update_play(draft, %{"is_complete" => false})
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 2}}}, 10_000

    assert in_site() == [kept.code]
    assert in_search() == [kept.code]
  end

  test "Generate rebuilds every play when the site's settings changed" do
    [a] = complete_plays(1)
    assert :started = SiteBuilder.generate(version: "1.0")
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 1}}}, 10_000
    plant(a)

    assert :started = SiteBuilder.generate(version: "2.0")
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 1}}}, 10_000
    assert rewritten?(a)
  end

  test "Rebuild rewrites every play though nothing changed" do
    [a] = complete_plays(1)
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 1}}}, 10_000
    plant(a)

    assert :started = SiteBuilder.rebuild([])
    assert_receive {:site_builder, :done, :rebuild, {:ok, %{plays: 1}}}, 10_000
    assert rewritten?(a)
  end
end
