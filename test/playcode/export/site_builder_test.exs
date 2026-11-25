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

  @tag :capture_log
  test "a job that crashes is reported, and the queue carries on" do
    # A code that is not a plain name cannot be a folder. The play form refuses one now,
    # so this is a row saved before it did.
    unchecked_code!(play_fixture(%{"is_complete" => true}), "bad/code")

    assert :started = SiteBuilder.generate([])
    # Invalid on purpose: Deployer rejects a repository without "/" before it pushes
    # anything, so this test can never reach GitHub.
    assert :queued = SiteBuilder.deploy("not a repo")

    events = events_until({:done, :deploy})
    assert {:failed, :generate} in events
    assert %{job: nil, progress: nil, queue: []} = SiteBuilder.status()
  end

  test "status names the running job and the requests waiting behind it" do
    play_fixture(%{"is_complete" => true})

    assert :started = SiteBuilder.generate([])
    assert :queued = SiteBuilder.deploy("not a repo")
    assert %{job: :generate, queue: [:deploy]} = SiteBuilder.status()

    events_until({:done, :deploy})
    assert %{job: nil, progress: nil, queue: []} = SiteBuilder.status()
  end

  # A deploy pushes the whole directory, so it waits for the build before it.
  test "a deploy asked for twice during a build is queued once and runs after it" do
    play_fixture(%{"is_complete" => true})
    assert :started = SiteBuilder.generate([])

    assert :queued = SiteBuilder.deploy("not a repo")
    assert :queued = SiteBuilder.deploy("not a repo")
    assert SiteBuilder.status().queue == [:deploy]

    events = events_until({:done, :deploy})
    assert Enum.count(events, &(&1 == {:started, :deploy})) == 1

    assert Enum.find_index(events, &(&1 == {:done, :generate})) <
             Enum.find_index(events, &(&1 == {:started, :deploy}))
  end

  # Regression: a deploy to a corrected repository was dropped as a duplicate, so the
  # first, mistyped, one ran.
  test "a request asked for again while waiting runs with the options of the latest ask" do
    play_fixture(%{"is_complete" => true})
    assert :started = SiteBuilder.generate([])

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
    assert %{job: nil, progress: nil, queue: []} = SiteBuilder.status()
    assert Process.whereis(SiteBuilder) == builder
    refute_receive {:site_builder, _, _, _}
  end

  # Rewriting a play deletes its folder first, so a file planted there says whether the
  # play was written again. File times have one-second resolution, too coarse here.
  defp sentinel(play), do: Path.join([StaticSite.output_dir(), "plays", play.code, "sentinel"])
  defp plant(play), do: File.write!(sentinel(play), "")
  defp rewritten?(play), do: not File.exists?(sentinel(play))

  # The site as a build with other assets left it: its record says so, a file is gone, and
  # every page links the assets with that build's stamp.
  defp stale_assets! do
    dir = StaticSite.output_dir()
    path = Path.join(dir, "build.json")

    File.write!(
      path,
      path |> File.read!() |> Jason.decode!() |> Map.put("assets", "older") |> Jason.encode!()
    )

    File.rm!(Path.join([dir, "assets", "style.css"]))

    for page <- pages() do
      File.write!(page, Regex.replace(~r/\?v=[0-9a-f]+/, File.read!(page), "?v=000000000000"))
    end
  end

  defp pages, do: Path.wildcard(Path.join(StaticSite.output_dir(), "**/*.html"))

  # The stamps the pages link the assets with, each once.
  defp stamps do
    pages()
    |> Enum.flat_map(&Regex.scan(~r/assets\/[\w.\/-]+\?v=([0-9a-f]+)/, File.read!(&1)))
    |> Enum.map(fn [_link, stamp] -> stamp end)
    |> Enum.uniq()
  end

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
    # A batch rewrites the shared assets, whatever it changes.
    assets = Path.join([StaticSite.output_dir(), "assets", "sentinel"])
    File.write!(assets, "")

    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 0, skipped: []}}}, 10_000
    refute rewritten?(a)
    assert File.exists?(assets)
  end

  # Regression: a site emptied of its plays kept build.json's fingerprint, so Generate
  # found it current and left it empty, under a hint that said it builds every complete
  # play.
  test "Generate builds every complete play in a site emptied of them" do
    [a] = complete_plays(1)
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 1}}}, 10_000
    {:ok, a} = Catalogue.update_play(a, %{"is_complete" => false})
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 1}}}, 10_000
    assert in_site() == []

    {:ok, _} = Catalogue.update_play(a, %{"is_complete" => true})
    b = complete_play()
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 2}}}, 10_000
    assert in_site() == Enum.sort([a.code, b.code])
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

  # A deploy that changed only priv/static_site (styles, scripts, fonts) made the next
  # Generate rebuild every play, minutes of CPU, for files no page embeds anything of but
  # their links. Those carry the assets' stamp, so a browser fetches the new ones instead
  # of pairing the pages with the styles it kept from an old visit (Hamlet's line numbers
  # and Folio passages, 2026-10-17): the links are moved to the new stamp in place.
  test "Generate updates the assets alone when only they changed, and every link to them" do
    [a] = complete_plays(1)
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 1}}}, 10_000
    assert [stamp] = stamps()
    plant(a)
    stale_assets!()

    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 0}}}, 10_000
    refute rewritten?(a)
    assert stamps() == [stamp]
    assert File.exists?(Path.join([StaticSite.output_dir(), "assets", "style.css"]))
    refute StaticSite.assets_changed?(StaticSite.output_dir())
  end

  test "a Generate that rewrites one play moves every page's links to the new assets" do
    [a, b] = complete_plays(2)
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 2}}}, 10_000
    assert [stamp] = stamps()
    plant(b)
    stale_assets!()

    {:ok, _} = Catalogue.update_play(a, %{"title" => "Revised"})
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 1}}}, 10_000
    refute rewritten?(b)
    assert stamps() == [stamp]
    refute StaticSite.assets_changed?(StaticSite.output_dir())
  end

  # Regression: a play marked complete reached a site that already held plays only
  # through its switch, while its page promised the next Generate would put it there.
  test "Generate adds a play marked complete since the last build" do
    [a] = complete_plays(1)
    b = play_fixture()
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 1}}}, 10_000

    {:ok, _} = Catalogue.update_play(b, %{"is_complete" => true})
    assert :started = SiteBuilder.generate([])
    assert_receive {:site_builder, :done, :generate, {:ok, %{changed: 1}}}, 10_000

    assert in_site() == Enum.sort([a.code, b.code])
    assert in_search() |> Enum.sort() == Enum.sort([a.code, b.code])
  end

  test "a whole-site rebuild also adds the complete plays the site lacks and leaves out drafts" do
    [a, c] = complete_plays(2)
    b = play_fixture()
    assert :started = SiteBuilder.generate(version: "1.0")
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 2}}}, 10_000

    {:ok, _} = Catalogue.update_play(c, %{"is_complete" => false})
    {:ok, _} = Catalogue.update_play(b, %{"is_complete" => true})
    assert :started = SiteBuilder.generate(version: "2.0")
    assert_receive {:site_builder, :done, :generate, {:ok, %{plays: 2}}}, 10_000

    assert in_site() == Enum.sort([a.code, b.code])
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
end
