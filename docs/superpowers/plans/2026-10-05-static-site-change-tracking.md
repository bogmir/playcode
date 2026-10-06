# Static Site Change Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The admin export page flags each published play that changed since it was written, with a Refresh button. Generate rewrites only the changed plays, unless the site's own code or settings changed, in which case it rebuilds them all.

**Architecture:**
- **Postgres keeps the change signal.** Triggers move `plays.content_version` whenever anything a play's pages show changes. They name no data column, and they notify `play_changed` on commit.
- **The site records its own build.** Every build writes `build.json` next to its files: a fingerprint of the code, assets and settings it was built with, and each play's version.
- **`SiteBuilder`'s Generate** compares the two and either rebuilds everything or runs one `apply_changes/2` batch.
- **A small listener** relays the notifications over PubSub to the export page, and to the content editor and play list on the play's own topic.

**Tech Stack:**
- Elixir 1.19, Phoenix 1.8, LiveView 1.1.
- PostgreSQL 16 (PL/pgSQL triggers, `pg_notify`), Ecto 3.14 (`writable: :never`, `read_after_writes`), `Postgrex.Notifications`.

**Spec:** `docs/superpowers/specs/2026-10-05-static-site-change-tracking-design.md`.

---

## Global Constraints

- **TDD, as `CLAUDE.md` requires.** For every test:
  - write the failing test first;
  - run it and see it fail for the expected reason;
  - write the smallest implementation that passes;
  - run it green;
  - **refactor while green.** Before the suite and commit step of every task: remove duplication, tighten names, match the surrounding code's idiom, and re-run the task's tests after each change. The code blocks in this plan are the minimum that passes, not a ceiling on clean-up. Behaviour does not change in this step; if a refactor needs a new test, it is not a refactor;
  - run the whole `mix test` before you claim anything works.
  - **Prove each new test bites.** Break the line it covers, watch it go red, put the line back, and say so in the commit message.
- **Run mix plainly:** `mix test`, `mix compile`. Never prefix a command with `export PATH=...`.
- **Before every commit:** `mix format`, then `mix compile --warnings-as-errors`.
- **Committing:**
  - stage files by path, never `git add -A`;
  - commit only on the feature branch;
  - never push or merge;
  - end every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Test through the outermost API:** a LiveView through `live/2`, the builder through its public functions, the site through `StaticSite`'s functions and the files it writes.
  - Read data back through context functions, not `Repo`.
  - The two tests that must reach past the contexts (the trigger tests' `next_transaction/0` and the trigger coverage query) say why in a comment.
- **Select page elements by visible text or a stable id:** `element("#play-#{id} button", t("Refresh"))`. Never by `phx-click` attributes, CSS classes or regexes over markup.
- **Spanish for every new string.** Put each user-visible string through `gettext`/`ngettext`, with a Spanish translation in `priv/gettext/es/LC_MESSAGES/default.po`. After `mix gettext.extract --merge`, check every entry it marks `fuzzy`: it fuzzy-matches new strings onto unrelated old translations.
- **The static site stays in English.** `StaticSite` already sets the locale; do not change that.
- **Over-flagging is accepted; missing a change is the bug.** A needless "Changed" costs a click. A missed one publishes a stale page.
- **No new dependencies.**
- **Do not delete any fixture.**
- **Do not migrate the dev database.** `mix test` migrates the test database; the dev one is the user's call.
- **Never write the lower-case old application name.** `test/rename_guard_test.exs` forbids it in tracked files.

## Review Focus

These are the five inputs the spec implies but its main-path tests would not exercise, most likely to bite first. Each one is pinned by a test in the task named.

1. **A site built before this feature** has files but no `build.json`.
   - Expected: every play in it counts as changed and the site counts as changed.
   - A single add must not make the site look current: the next Generate is a full rebuild.
   - Task 3, "a site with no build record…".
2. **A `build.json` that cannot be read** (a crash mid-write, a hand edit).
   - Expected: treated as no record. It must not crash the page or the builder.
   - Task 3, "an unreadable build record counts as none".
3. **A site begun with the switches alone,** with Generate never pressed.
   - Expected: no "design or settings changed" banner, and Generate is incremental.
   - Task 3, "a site begun by adding plays one at a time is current".
4. **The admin edits the Version field.**
   - Expected: the banner appears, and Generate rebuilds every play, because every page footer shows the version.
   - Task 6, "a new version is a change to the whole site…".
5. **A `play_changed` notification for a play that is not in the site, or no longer exists.**
   - Expected: the page neither crashes nor flags anything.
   - Task 6, "a change to a play that no longer exists flags nothing".

## Rulings made while planning

These were checked against the code and against Postgres 16, in a transaction that was rolled back. The spec has been updated to match.

- **Five SQL functions, not four.**
  - `touch_play`;
  - `play_row_changed`, the generic trigger;
  - `element_character_changed`;
  - `play_changed`, one function for the plays BEFORE and AFTER triggers;
  - `place_changed`, one function for `places` and `place_names`, given the column that names the place.
- **The place column is `parent_place_id`,** not `parent_id`.
- **Inserting or purging a play touches no relative.** Relatives' pages list only *published* plays, and publishing or unpublishing already re-exports them.
- **The sandbox is one transaction per test,** and a play moves once per transaction.
  - The trigger tests run `next_transaction/0` between edits.
  - Every other test edits the play's own row, whose BEFORE trigger always moves it.
- **`build.json` keeps `"site": null` when the fingerprint is unknown.** A batch that starts from an empty site records the current fingerprint.
- **`StaticSite.outdated/1` is public.** The builder runs it; it is tested on its own.
- **Edition order.** `StaticSite.Edition.load/1` reads the play row before its content, so a recorded version is never newer than the published text. A race cannot be tested deterministically, so this one is code order plus a comment.
- **Generate with nothing to do writes nothing.**
- **Which plays were rewritten is checked with a sentinel file,** not mtimes: Erlang's file times have one-second resolution.
- **The flash and the hint must not share text,** because tests wait for the flash.
  - Generate's hint, when nothing changed, says "Every play in the site is up to date."
  - The flash says "Nothing has changed since the last build."
- **The fingerprint includes `PlaycodeWeb.Gettext`,** as the spec says. A Spanish translation edit therefore causes a full rebuild; that over-flag is accepted.
- **Measured trigger cost:** rewriting the 8,341 elements of the largest dev play takes about 0.25 s longer than without the triggers.
- **The listener also relays to `play_content:<id>`** (added 2026-10-06, Task 5 Steps 6–10).
  - The content editor and the play list subscribe there, but only the content editor ever broadcast, so imports, the metadata form and other admins' edits left them stale.
  - `broadcast_content_changed/1` stops broadcasting and becomes `refresh_derived/1`.
  - Checked by removing the broadcast line and running both pages' tests: 12 tests, 0 failures. Every editor handler reloads its own assigns; the broadcast only reached other sessions.

## Files

| File | Task | What it is |
|---|---|---|
| `priv/repo/migrations/20261005120000_track_play_content_version.exs` | 1 | sequence, columns, five functions, triggers |
| `lib/playcode/catalogue/play.ex` | 1 | read-only `content_version` field |
| `test/playcode/content_version_test.exs` | 1 | trigger behaviour + trigger coverage guard |
| `lib/playcode/export/static_site/fingerprint.ex` | 2 | `Fingerprint.modules/0`, `Fingerprint.current/1` |
| `test/playcode/export/static_site/fingerprint_test.exs` | 2 | fingerprint + module coverage guard |
| `lib/playcode/export/static_site.ex` | 3 | `build.json`, `changed_plays/1`, `site_changed?/2`, `outdated/1` |
| `lib/playcode/export/static_site/edition.ex` | 3 | play row read first |
| `test/support/static_site_helpers.ex` | 3 | `site_dir!/0` |
| `test/playcode/export/static_site_changes_test.exs` | 3 | the build record |
| `lib/playcode/export/site_builder.ex` | 4 | incremental `:generate`, new `:rebuild` |
| `test/playcode/export/site_builder_test.exs` | 4 | Generate and Rebuild through the builder |
| `lib/playcode/export/play_change_listener.ex` | 5 | `Postgrex.Notifications` → PubSub |
| `lib/playcode/application.ex` | 5 | start the listener |
| `test/playcode/export/play_change_listener_test.exs` | 5 | a committed edit reaches both topics |
| `lib/playcode/play_content.ex` | 5 | `notify_changed/1`; `broadcast_content_changed/1` becomes `refresh_derived/1` |
| `lib/playcode_web/live/admin/play_content_editor_live.ex` | 5 | calls `refresh_derived/1` |
| `CLAUDE.md` | 5 | the statistics line names `refresh_derived/1` |
| `lib/playcode_web/live/admin/export_site_live.ex` | 6 | badge, Refresh, hint, banner, Rebuild everything, flashes |
| `priv/gettext/**` | 6 | Spanish |
| `test/playcode_web/live/admin/export_site_live_test.exs` | 6 | the page |
| `CLAUDE.md` | 6 | documentation |
| `lib/playcode/import/tei_parser.ex` | 7 | re-import drops cached statistics |
| `lib/playcode/catalogue.ex` | 7 | stable ordering of relatives, notes, place names |
| `test/playcode/import/tei_parser_test.exs`, `test/playcode/export/static_site_test.exs`, `test/playcode/export/tei_xml_test.exs` | 7 | the fixes |

---

### Task 1: `plays.content_version`, kept by Postgres

**Files:**
- Create: `priv/repo/migrations/20261005120000_track_play_content_version.exs`
- Modify: `lib/playcode/catalogue/play.ex` (the field list, after `field :deleted_at`)
- Test: `test/playcode/content_version_test.exs`

**Interfaces:**
- Produces:
  - `%Play{}.content_version`: an integer, read back after every insert and update (`read_after_writes: true`) and never cast (`writable: :never`).
  - The Postgres notification channel `play_changed`, whose payload is the play id as text.
  - The trigger function `play_row_changed()`, which a future table attaches.

- [ ] **Step 1: Write the failing tests**

Create `test/playcode/content_version_test.exs`:

```elixir
defmodule Playcode.ContentVersionTest do
  @moduledoc """
  `plays.content_version`, which Postgres moves whenever something a play's static pages
  show changes, so the export can tell which published plays are out of date. Every edit
  goes through a context; the version is read back with `Catalogue.get_play!/2`.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.{Catalogue, PlayContent, Places, Statistics}

  # Postgres moves a play once per transaction, and the sandbox runs the whole test in
  # one. This stands in for the commit between two edits. It reaches past the contexts
  # because nothing outside the database can end a transaction inside the sandbox.
  defp next_transaction do
    Playcode.Repo.query!(
      "UPDATE plays SET content_txid = NULL WHERE content_txid = txid_current()"
    )
  end

  defp version(play), do: Catalogue.get_play!(play.id, include_deleted: true).content_version

  # Whether `edit`, run as a transaction of its own, moves `play`'s version.
  defp moves?(play, edit) do
    next_transaction()
    before = version(play)
    edit.()
    version(play) > before
  end

  test "a new play has a version" do
    assert is_integer(play_fixture().content_version)
  end

  test "every edit to the text, cast, credits, notes or places moves the play" do
    %{play: play, character: character, act: act, speech: speech, verse_line: line} =
      play_with_structure_fixture()

    place = place_fixture()

    edits = [
      division: fn -> PlayContent.update_division(act, %{title: "ACTO I"}) end,
      element: fn -> PlayContent.update_element(line, %{content: "Otro verso"}) end,
      character: fn -> PlayContent.update_character(character, %{name: "BETA"}) end,
      speaker: fn -> PlayContent.set_element_characters(speech.id, []) end,
      editor: fn ->
        Catalogue.create_play_editor(%{
          play_id: play.id,
          person_name: "Ed",
          role: "editor",
          position: 1
        })
      end,
      source: fn ->
        Catalogue.create_play_source(%{play_id: play.id, title: "Fuente", position: 1})
      end,
      note: fn ->
        Catalogue.create_play_editorial_note(%{
          play_id: play.id,
          section_type: "nota",
          content: "Nota",
          position: 1
        })
      end,
      place: fn -> play_place_fixture(play, place) end,
      deletion: fn -> PlayContent.delete_element(line) end
    ]

    for {what, edit} <- edits do
      assert moves?(play, edit), "#{what} did not move the play's version"
    end
  end

  test "several edits in one transaction move the play once" do
    %{play: play, act: act, scene: scene} = play_with_structure_fixture()

    next_transaction()
    {:ok, _} = PlayContent.update_division(act, %{title: "ACTO I"})
    once = version(play)
    {:ok, _} = PlayContent.update_division(scene, %{title: "ESCENA I"})

    assert version(play) == once
  end

  test "a change to a play's own fields moves it, its original and its translations" do
    %{original: original, translation: translation} = translation_family_fixture()
    unrelated = play_fixture()
    plays = [original, translation, unrelated]

    next_transaction()
    before = Enum.map(plays, &version/1)
    {:ok, _} = Catalogue.update_play(original, %{"title" => "Nuevo título"})

    assert Enum.zip_with(plays, before, &(version(&1) > &2)) == [true, true, false]
  end

  # Only a play's own row shows on its relatives' title pages.
  test "an edit to a play's text moves that play and no other" do
    %{original: original, translation: translation} = translation_family_fixture()

    next_transaction()
    {original_before, translation_before} = {version(original), version(translation)}

    {:ok, _} =
      PlayContent.create_division(%{
        play_id: translation.id,
        type: "acto",
        number: 1,
        position: 1
      })

    assert version(translation) > translation_before
    assert version(original) == original_before
  end

  test "an edit to a place moves every play set there or anywhere inside it" do
    country = place_fixture(%{"type" => "country"})
    city = place_fixture(%{"parent_place_id" => country.id})
    play = play_fixture()
    play_place_fixture(play, city)
    elsewhere = play_fixture()
    play_place_fixture(elsewhere, place_fixture())

    note = fn -> Places.update_place(Places.get_place!(country.id), %{"note" => "Reino"}) end

    # The slug is passed so that only the name changes, not the places row.
    rename = fn ->
      reloaded = Places.get_place!(country.id)
      [name] = reloaded.names

      Places.update_place(reloaded, %{
        "slug" => reloaded.slug,
        "names" => [%{"id" => name.id, "name" => "Hispania"}]
      })
    end

    assert moves?(play, note)
    assert moves?(play, rename)
    refute moves?(elsewhere, note)
  end

  test "caching a play's statistics does not move it" do
    %{play: play} = play_with_structure_fixture()
    refute moves?(play, fn -> Statistics.recompute(play.id) end)
  end

  # A new table whose rows appear on a play's pages needs the trigger, one line in its
  # migration (see the moduledoc of
  # priv/repo/migrations/20261005120000_track_play_content_version.exs).
  test "every table with a play_id has the content trigger, or is not page data" do
    # Statistics are derived from the text and written by the export itself; the
    # activity log is an audit trail.
    not_page_data = ~w(play_statistics activity_logs)

    # Reads the schema itself: no context describes triggers.
    %{rows: rows} =
      Playcode.Repo.query!("""
      SELECT c.table_name,
             (SELECT count(DISTINCT t.event_manipulation)
                FROM information_schema.triggers t
               WHERE t.event_object_schema = c.table_schema
                 AND t.event_object_table = c.table_name
                 AND t.action_statement = 'EXECUTE FUNCTION play_row_changed()') = 3
        FROM information_schema.columns c
       WHERE c.table_schema = 'public' AND c.column_name = 'play_id'
      """)

    untracked = for [table, false] <- rows, table not in not_page_data, do: table
    assert untracked == []
  end
end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/playcode/content_version_test.exs`
Expected: FAIL. `content_version` is not a field of `Play` (a `KeyError`), the `content_txid` column does not exist, and the guard lists all seven play tables.

- [ ] **Step 3: Write the migration**

Create `priv/repo/migrations/20261005120000_track_play_content_version.exs`:

```elixir
defmodule Playcode.Repo.Migrations.TrackPlayContentVersion do
  @moduledoc """
  `plays.content_version`: Postgres moves it whenever something a play's static pages
  show changes, so the export can tell which published plays are out of date. Spec:
  docs/superpowers/specs/2026-10-05-static-site-change-tracking-design.md.

  None of the functions names a data column, so adding a column to any table needs
  nothing. A new *table* with a `play_id` whose rows appear on a play's pages needs one
  line in its own migration:

      execute "CREATE TRIGGER my_table_touch_play AFTER INSERT OR UPDATE OR DELETE ON my_table FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
              "DROP TRIGGER my_table_touch_play ON my_table"

  test/playcode/content_version_test.exs fails until it has it.
  """
  use Ecto.Migration

  # The tables with a play_id whose rows appear on a play's pages.
  @play_tables ~w(play_divisions play_elements characters play_editors play_sources
                  play_editorial_notes play_places)

  # True when an UPDATE of plays changed more than the bookkeeping columns. Moving the
  # version alone passes neither plays trigger, so a touch never fans out again.
  @data_changed """
  to_jsonb(OLD) - '{content_version,content_txid,updated_at}'::text[]
    IS DISTINCT FROM to_jsonb(NEW) - '{content_version,content_txid,updated_at}'::text[]
  """

  def up do
    execute "CREATE SEQUENCE play_content_version"

    alter table(:plays) do
      add :content_version, :bigint,
        null: false,
        default: fragment("nextval('play_content_version')")

      # The transaction that last moved content_version: it moves once per transaction.
      add :content_txid, :bigint
    end

    execute "ALTER SEQUENCE play_content_version OWNED BY plays.content_version"

    # Moves a play once per transaction, so an import writing thousands of rows updates
    # the play row once, and tells Playcode.Export.PlayChangeListener. Postgres sends the
    # notification on commit, one per play per transaction.
    execute """
    CREATE FUNCTION touch_play(play uuid) RETURNS void AS $$
    BEGIN
      UPDATE plays
         SET content_version = nextval('play_content_version'), content_txid = txid_current()
       WHERE id = play AND content_txid IS DISTINCT FROM txid_current();

      IF FOUND THEN
        PERFORM pg_notify('play_changed', play::text);
      END IF;
    END
    $$ LANGUAGE plpgsql
    """

    # A row of one of @play_tables changed. Both plays, for a row moved between them;
    # OLD is NULL on INSERT and NEW on DELETE, and touch_play(NULL) touches nothing.
    execute """
    CREATE FUNCTION play_row_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(OLD.play_id);
      PERFORM touch_play(NEW.play_id);
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # A speech's speakers changed: the play of the speech.
    execute """
    CREATE FUNCTION element_character_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id) FROM play_elements WHERE id IN (OLD.element_id, NEW.element_id);
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # A play's own row changed. BEFORE: its new version. AFTER: the plays whose title
    # pages show it, its original (before and after) and its translations.
    execute """
    CREATE FUNCTION play_changed() RETURNS trigger AS $$
    BEGIN
      IF TG_WHEN = 'BEFORE' THEN
        NEW.content_version := nextval('play_content_version');
        NEW.content_txid := txid_current();
        RETURN NEW;
      END IF;

      PERFORM pg_notify('play_changed', NEW.id::text);

      PERFORM touch_play(id)
         FROM plays
        WHERE id IN (OLD.parent_play_id, NEW.parent_play_id) OR parent_play_id = NEW.id;

      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # A place or one of its names changed: every play set there or anywhere inside it,
    # whose pages and TEI show the place with its ancestors. TG_ARGV[0] names the column
    # holding the place's id.
    execute """
    CREATE FUNCTION place_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id)
         FROM play_places
        WHERE place_id IN (
          WITH RECURSIVE tree(id) AS (
            SELECT (to_jsonb(OLD) ->> TG_ARGV[0])::uuid
            UNION
            SELECT (to_jsonb(NEW) ->> TG_ARGV[0])::uuid
            UNION
            SELECT places.id FROM places JOIN tree ON places.parent_place_id = tree.id
          )
          SELECT id FROM tree
        );

      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    for table <- @play_tables do
      execute """
      CREATE TRIGGER #{table}_touch_play AFTER INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION play_row_changed()
      """
    end

    execute """
    CREATE TRIGGER element_characters_touch_play
      AFTER INSERT OR UPDATE OR DELETE ON element_characters
      FOR EACH ROW EXECUTE FUNCTION element_character_changed()
    """

    execute """
    CREATE TRIGGER plays_bump BEFORE UPDATE ON plays
      FOR EACH ROW WHEN (#{@data_changed}) EXECUTE FUNCTION play_changed()
    """

    execute """
    CREATE TRIGGER plays_touch_relatives AFTER UPDATE ON plays
      FOR EACH ROW WHEN (#{@data_changed}) EXECUTE FUNCTION play_changed()
    """

    # A new place has no plays yet, and a place a play links to cannot be deleted.
    execute """
    CREATE TRIGGER places_touch_plays AFTER UPDATE ON places
      FOR EACH ROW EXECUTE FUNCTION place_changed('id')
    """

    execute """
    CREATE TRIGGER place_names_touch_plays AFTER INSERT OR UPDATE OR DELETE ON place_names
      FOR EACH ROW EXECUTE FUNCTION place_changed('place_id')
    """
  end

  def down do
    # CASCADE drops the triggers that call each function.
    for function <- ~w[play_row_changed() element_character_changed() play_changed() place_changed()] do
      execute "DROP FUNCTION #{function} CASCADE"
    end

    execute "DROP FUNCTION touch_play(uuid)"

    # Dropping the column drops the sequence it owns.
    alter table(:plays) do
      remove :content_version
      remove :content_txid
    end
  end
end
```

- [ ] **Step 4: Add the field to `Play`**

In `lib/playcode/catalogue/play.ex`, right after `field :deleted_at, :utc_datetime`:

```elixir
    # Moved by Postgres whenever something this play's static pages show changes
    # (migration 20261005120000_track_play_content_version). Never written from here.
    field :content_version, :integer, writable: :never, read_after_writes: true
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `mix test test/playcode/content_version_test.exs`
Expected: PASS, 8 tests. `mix test` migrates the test database first.

- [ ] **Step 6: Prove the tests bite**

This step uses two rollback cycles. Each edit changes the migration, so roll it back and let `mix test` migrate again.

1. **The table list, the guard and the statistics exclusion.**
   - In the migration, remove `play_editors` from `@play_tables` and add `play_statistics`.
   - Run `MIX_ENV=test mix ecto.rollback --step 1`, then `mix test test/playcode/content_version_test.exs`.
   - Expected, three failures:
     - "editor did not move the play's version";
     - the guard lists `"play_editors"`;
     - "caching a play's statistics does not move it".
   - Restore the list, roll back again, rerun: green.
2. **The `WHEN` on the AFTER trigger.**
   - Remove ` WHEN (#{@data_changed})` from `plays_touch_relatives`.
   - Roll back, then run.
   - Expected failure: "an edit to a play's text moves that play and no other". The original moves, because touching the translation fans out.
   - Restore, roll back, rerun: green.

- [ ] **Step 7: Run the whole suite**

Run: `mix test`
Expected: all pass. No existing test compares whole play structs (checked while planning). If one fails on a struct comparison, it is because `content_version` moved; compare ids or fields instead, and say why in a comment.

- [ ] **Step 8: Format, compile, commit**

```bash
mix format
mix compile --warnings-as-errors
git add priv/repo/migrations/20261005120000_track_play_content_version.exs lib/playcode/catalogue/play.ex test/playcode/content_version_test.exs
git commit -m "feat: Postgres moves plays.content_version when a play's pages would change

Triggers on the play tables, speakers, the plays row and the gazetteer bump a
play once per transaction and notify play_changed. A guard test fails for any
play_id table without the trigger. Bites: dropping play_editors from the list,
tracking play_statistics, and removing the AFTER trigger's WHEN each turn a
test red.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The site fingerprint

**Files:**
- Create: `lib/playcode/export/static_site/fingerprint.ex`
- Test: `test/playcode/export/static_site/fingerprint_test.exs`

**Interfaces:**
- Produces:
  - `Playcode.Export.StaticSite.Fingerprint.modules() :: [module]`, sorted.
  - `Playcode.Export.StaticSite.Fingerprint.current(opts :: keyword) :: String.t()`: 64 lower-case hex characters. It reads only `opts[:version]`.

- [ ] **Step 1: Write the failing tests**

Create `test/playcode/export/static_site/fingerprint_test.exs`:

```elixir
defmodule Playcode.Export.StaticSite.FingerprintTest do
  @moduledoc """
  The site fingerprint: one hash of everything the static pages are built with but the
  play data. When it differs from the one a site was built with, Generate rebuilds every
  play.
  """
  use ExUnit.Case, async: true

  alias Playcode.Export.StaticSite.Fingerprint

  test "the same settings give the same fingerprint, another version another" do
    assert Fingerprint.current(version: "1.0") == Fingerprint.current(version: "1.0")
    assert Fingerprint.current(version: "1.0") != Fingerprint.current(version: "1.1")
  end

  # What these return is play data, which plays.content_version tracks. Ecto schemas
  # count too.
  @data_access [Playcode.Catalogue, Playcode.PlayContent, Playcode.Repo]

  test "every module the export calls is in the fingerprint, or only reads play data" do
    reached = reach(Fingerprint.modules(), MapSet.new())
    assert Enum.reject(reached, &(&1 in Fingerprint.modules() or data_access?(&1))) == []
  end

  # Follows the remote calls out of the fingerprinted modules, through every module of
  # this app they reach, stopping at data access.
  defp reach([], seen), do: seen

  defp reach([module | rest], seen) do
    cond do
      module in seen ->
        reach(rest, seen)

      module not in Fingerprint.modules() and data_access?(module) ->
        reach(rest, MapSet.put(seen, module))

      true ->
        reach(rest ++ calls(module), MapSet.put(seen, module))
    end
  end

  defp data_access?(module) do
    Code.ensure_loaded!(module)
    module in @data_access or function_exported?(module, :__schema__, 1)
  end

  # This app's modules that `module` calls, from the imports in its compiled BEAM file.
  defp calls(module) do
    ours = Application.spec(:playcode, :modules)
    {:ok, {^module, [imports: imports]}} = :beam_lib.chunks(:code.which(module), [:imports])
    for {callee, _function, _arity} <- imports, callee in ours, uniq: true, do: callee
  end
end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/playcode/export/static_site/fingerprint_test.exs`
Expected: FAIL with `UndefinedFunctionError` for `Fingerprint.current/1` and `Fingerprint.modules/0`.

- [ ] **Step 3: Write the module**

Create `lib/playcode/export/static_site/fingerprint.ex`:

```elixir
defmodule Playcode.Export.StaticSite.Fingerprint do
  @moduledoc """
  Everything the static site's pages are built with except the play data, as one hash.
  `build.json` records the one a site was built with; when the current one differs, any
  page may be out of date, and Generate rebuilds every play.

  It covers the code (`module_info(:md5)` of `modules/0`), the files under
  `priv/static_site`, the versions of the libraries that render and encode the pages,
  and the `:version` option. Not `build_date`: a page's footer says when that page was
  written. Not `base_url`: nothing reads it. The play data is `plays.content_version`'s.

  `test/playcode/export/static_site/fingerprint_test.exs` fails when the export starts
  calling a module of this app that is neither listed here nor data access.
  """

  @prefix "Elixir.Playcode.Export.StaticSite"

  # The modules outside StaticSite whose code shapes a page.
  @modules [
    Playcode.Export.TeiXml,
    Playcode.Statistics,
    Playcode.Statistics.Metrics,
    Playcode.Catalogue.Play,
    Playcode.PlayContent.InlineMarkup,
    Playcode.PlayContent.Element,
    Playcode.Places,
    PlaycodeWeb.PlayLabels,
    PlaycodeWeb.Gettext
  ]

  @libraries [:phoenix_live_view, :phoenix_html, :jason, :xml_builder]

  @doc """
  Every `Playcode.Export.StaticSite*` module and the modules listed above. Read from the
  application's module list, not the loaded modules: in dev a module loads on first use,
  so a list of loaded ones would differ before and after the first build.
  """
  def modules do
    exported =
      Enum.filter(
        Application.spec(:playcode, :modules),
        &String.starts_with?(Atom.to_string(&1), @prefix)
      )

    Enum.sort(exported ++ @modules)
  end

  @doc "A hex SHA-256 of what the pages are built with, for the `:version` in `opts`."
  def current(opts) do
    code = Enum.map(modules(), &{&1, &1.module_info(:md5)})
    libraries = Enum.map(@libraries, &{&1, Application.spec(&1, :vsn)})

    {code, assets(), libraries, opts[:version]}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Each file under priv/static_site, by its path there, with its contents.
  defp assets do
    dir = Application.app_dir(:playcode, "priv/static_site")

    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map(&{Path.relative_to(&1, dir), File.read!(&1)})
  end
end
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/playcode/export/static_site/fingerprint_test.exs`
Expected: PASS, 2 tests. The module list was checked against the compiled code while planning: nothing is left unfingerprinted.

- [ ] **Step 5: Prove the tests bite**

1. Remove `PlaycodeWeb.PlayLabels` from `@modules`. Run the test. Expected: the guard fails with `[PlaycodeWeb.PlayLabels]`. Restore it.
2. Replace `opts[:version]` in `current/1` with `nil`. Run. Expected: the version test fails. Restore it.

- [ ] **Step 6: Run the whole suite, format, compile, commit**

```bash
mix test
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/static_site/fingerprint.ex test/playcode/export/static_site/fingerprint_test.exs
git commit -m "feat: a fingerprint of the code, assets and settings the site is built with

A guard test follows the export's remote calls and fails for any module of the
app that is neither fingerprinted nor data access. Bites: dropping PlayLabels
from the list, and leaving the version out of the hash.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The site records its build

**Files:**
- Modify: `lib/playcode/export/static_site.ex`:
  - the alias line;
  - the moduledoc;
  - `generate/1`, `apply_changes/2` and `build_play/3`;
  - new public `changed_plays/1`, `site_changed?/2` and `outdated/1`;
  - private `read_build/1` and `write_build/3`.
- Modify: `lib/playcode/export/static_site/edition.ex` (`load/1`)
- Modify: `test/support/static_site_helpers.ex` (new `site_dir!/0`, used by `generate!/2`)
- Test: `test/playcode/export/static_site_changes_test.exs`

**Interfaces:**
- Consumes:
  - `%Play{}.content_version` (Task 1);
  - `Fingerprint.current/1` (Task 2).
- Produces:
  - `StaticSite.changed_plays(dir :: Path.t()) :: [code :: String.t()]`: the published (complete, not archived) plays on disk whose version differs from the recorded one, in title order.
  - `StaticSite.site_changed?(dir :: Path.t(), opts :: keyword \\ []) :: boolean`: reads `opts[:version]`.
  - `StaticSite.outdated(dir :: Path.t()) :: [{:add, play_id} | {:remove, code}]`
  - `build.json` at the site root: `{"site": fingerprint | null, "plays": {code: content_version}}`.
  - `Playcode.StaticSiteHelpers.site_dir!/0`: a fresh temporary directory, removed when the test exits.

- [ ] **Step 1: Add `site_dir!/0` to the helpers**

In `test/support/static_site_helpers.ex`, replace the first two lines of `generate!/2`'s body:

```elixir
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
```

with:

```elixir
    dir = site_dir!()
```

and add, after `generate!/2`:

```elixir
  @doc "A fresh temp directory for a site, removed when the test exits."
  def site_dir! do
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
```

- [ ] **Step 2: Write the failing tests**

Create `test/playcode/export/static_site_changes_test.exs`:

```elixir
defmodule Playcode.Export.StaticSiteChangesTest do
  @moduledoc """
  What a site records about its own build (`build.json`), and what it says has changed
  since: `changed_plays/1`, `site_changed?/2` and `outdated/1`. Built with `generate/1`
  and `apply_changes/2` into a temp directory; plays edited through the Catalogue.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Catalogue
  alias Playcode.Export.StaticSite

  defp complete_play(attrs \\ %{}), do: play_fixture(Map.put(attrs, "is_complete", true))

  test "a play edited since the site was built is changed until it is written again" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a, b])
    assert StaticSite.changed_plays(dir) == []

    {:ok, _} = Catalogue.update_play(a, %{"title" => "Revised"})
    assert StaticSite.changed_plays(dir) == [a.code]

    {:ok, _} = StaticSite.apply_changes([{:add, a.id}], output_dir: dir)
    assert StaticSite.changed_plays(dir) == []
  end

  test "a site is current for the version it was built with, and changed for any other" do
    dir = generate!([complete_play()], version: "2.0")

    refute StaticSite.site_changed?(dir, version: "2.0")
    assert StaticSite.site_changed?(dir, version: "2.1")
  end

  # Its other pages still show the version they were built with.
  test "adding a play under other settings does not make the site look built with them" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a], version: "2.0")

    {:ok, _} = StaticSite.apply_changes([{:add, b.id}], output_dir: dir, version: "3.0")

    refute StaticSite.site_changed?(dir, version: "2.0")
    assert StaticSite.changed_plays(dir) == []
  end

  # Review Focus 1: a site built before build.json existed was written by unknown code.
  test "a site with no build record has changed, and so has every play in it" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a, b])
    File.rm!(Path.join(dir, "build.json"))

    assert StaticSite.site_changed?(dir)
    assert Enum.sort(StaticSite.changed_plays(dir)) == Enum.sort([a.code, b.code])

    {:ok, _} = StaticSite.apply_changes([{:add, a.id}], output_dir: dir)

    assert StaticSite.changed_plays(dir) == [b.code]
    assert StaticSite.site_changed?(dir)
  end

  # Review Focus 2.
  test "an unreadable build record counts as none" do
    a = complete_play()
    dir = generate!([a])
    File.write!(Path.join(dir, "build.json"), ~s({"site": "abc", "pla))

    assert StaticSite.site_changed?(dir)
    assert StaticSite.changed_plays(dir) == [a.code]
  end

  # Review Focus 3: the batch wrote every page there is, so it knows what built them.
  test "a site begun by adding plays one at a time is current" do
    a = complete_play()
    dir = site_dir!()

    {:ok, _} = StaticSite.apply_changes([{:add, a.id}], output_dir: dir)

    refute StaticSite.site_changed?(dir)
    assert StaticSite.changed_plays(dir) == []
  end

  test "outdated adds each changed play and removes each one no longer published" do
    [changed, same, archived, draft] = for _ <- 1..4, do: complete_play()
    dir = generate!([changed, same, archived, draft])

    {:ok, _} = Catalogue.update_play(changed, %{"title" => "Revised"})
    {:ok, _} = Catalogue.delete_play(archived)
    {:ok, _} = Catalogue.update_play(draft, %{"is_complete" => false})

    assert Enum.sort(StaticSite.outdated(dir)) ==
             Enum.sort([{:add, changed.id}, {:remove, archived.code}, {:remove, draft.code}])
  end
end
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `mix test test/playcode/export/static_site_changes_test.exs`
Expected: FAIL with `UndefinedFunctionError` for `StaticSite.changed_plays/1`, `site_changed?/2` and `outdated/1`.

- [ ] **Step 4: Read the play row first in `Edition.load/1`**

In `lib/playcode/export/static_site/edition.ex`, change `load/1` so that it begins:

```elixir
  def load(id) do
    # The play first: its content_version is what build.json records, so content read
    # after it can only be newer. A play edited mid-load stays flagged as changed, never
    # published stale and recorded as current.
    play = Catalogue.get_play_with_all!(id)
    divisions = PlayContent.load_play_content(id)
```

In the struct literal, replace `play: Catalogue.get_play_with_all!(id),` with `play: play,`.

- [ ] **Step 5: Record and read the build in `StaticSite`**

In `lib/playcode/export/static_site.ex`:

1. Change the alias line to:

```elixir
  alias Playcode.Export.StaticSite.{Components, Edition, Fingerprint, Pages, Search}
```

2. Append this paragraph to the `@moduledoc`, before its closing `"""`:

```
  Every build records itself in `build.json` at the site root: the fingerprint of what
  built it (`StaticSite.Fingerprint`) and each play's `content_version`. From it
  `changed_plays/1`, `site_changed?/2` and `outdated/1` say what changed since.
```

3. In `build_play/3`, make the merged map carry the play's version:

```elixir
      |> Map.merge(%{
        code: edition.play.code,
        version: edition.play.content_version,
        postings: Search.write_play(dir, edition)
      })
```

4. In `generate/1`, right after `report = write_search(...)`, add:

```elixir
        # Last: a build cut short leaves no record, so the next Generate rebuilds it all.
        write_build(dir, Fingerprint.current(opts), Map.new(results, &{&1.code, &1.version}))
```

5. In `apply_changes/2`, read the record before anything is written. Right after `on_disk = MapSet.new(list_exported_codes(dir))`, add:

```elixir
      built = read_build(dir)
```

Then replace the last two lines of the `in_english` function:

```elixir
      write_search(plays, Map.new(added ++ refreshed, &{&1.code, &1.postings}), dir)
      {:ok, %{skipped: skipped}}
```

with:

```elixir
      write_search(plays, Map.new(added ++ refreshed, &{&1.code, &1.postings}), dir)

      # Last, as in generate/1. A batch that began on an empty site wrote every page
      # there is, so it records what built them; otherwise the site's record stands.
      fingerprint = if MapSet.size(on_disk) == 0, do: Fingerprint.current(opts), else: built.site
      written = Map.new(added ++ refreshed, &{&1.code, &1.version})
      write_build(dir, fingerprint, built.plays |> Map.drop(removes) |> Map.merge(written))
      {:ok, %{skipped: skipped}}
```

6. After `list_exported_codes/1`, add the three public functions:

```elixir
  @doc """
  Codes of the plays in the site at `dir` that changed since they were written: the
  published plays whose `content_version` is not the one `build.json` records for them.
  A play it records nothing for counts as changed. Archived and incomplete plays are
  `outdated/1`'s to remove.
  """
  def changed_plays(dir) do
    built = read_build(dir).plays
    on_disk = MapSet.new(list_exported_codes(dir))

    for play <- Catalogue.list_plays(complete: true),
        MapSet.member?(on_disk, play.code),
        built[play.code] != play.content_version,
        do: play.code
  end

  @doc """
  Whether the site at `dir` may be out of date as a whole: `build.json` records no
  fingerprint, or another than `Fingerprint.current/1` gives for `opts` (`:version`).
  """
  def site_changed?(dir, opts \\ []),
    do: read_build(dir).site != Fingerprint.current(defaults(opts))

  @doc """
  The batch that brings the site at `dir` up to date through `apply_changes/2`: each
  changed play added again, each play on disk no longer published (archived, deleted or
  no longer complete) removed.
  """
  def outdated(dir) do
    published = Catalogue.list_plays(complete: true)
    live = MapSet.new(published, & &1.code)
    changed = MapSet.new(changed_plays(dir))

    adds = for play <- published, MapSet.member?(changed, play.code), do: {:add, play.id}

    removes =
      for code <- list_exported_codes(dir), not MapSet.member?(live, code), do: {:remove, code}

    adds ++ removes
  end
```

7. After `published_plays/1`, add the private pair:

```elixir
  @build "build.json"

  # What build.json records: the fingerprint the site was built with (nil if unknown)
  # and each play's content_version. No file, or one that cannot be read, records
  # nothing, so the site and every play in it count as changed.
  defp read_build(dir) do
    with {:ok, json} <- File.read(Path.join(dir, @build)),
         {:ok, %{"plays" => %{} = plays} = build} <- Jason.decode(json) do
      %{site: build["site"], plays: plays}
    else
      _ -> %{site: nil, plays: %{}}
    end
  end

  defp write_build(dir, fingerprint, plays) do
    json = Jason.encode!(%{site: fingerprint, plays: plays}, pretty: true)
    File.write!(Path.join(dir, @build), json)
  end
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/playcode/export/static_site_changes_test.exs`
Expected: PASS, 7 tests.

- [ ] **Step 7: Prove the tests bite**

1. In `apply_changes/2`, replace `if MapSet.size(on_disk) == 0, do: Fingerprint.current(opts), else: built.site` with `built.site`. Expected: "a site begun by adding plays one at a time is current" fails. Restore it.
2. In `build_play/3`, change `version: edition.play.content_version` to `version: nil`. Expected: the first test fails, because every play counts as changed right after `generate/1`. Restore it.

- [ ] **Step 8: Run the whole suite, format, compile, commit**

```bash
mix test
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/static_site.ex lib/playcode/export/static_site/edition.ex test/support/static_site_helpers.ex test/playcode/export/static_site_changes_test.exs
git commit -m "feat: a built site records its fingerprint and each play's version

build.json at the site root lets changed_plays/1, site_changed?/2 and
outdated/1 say what changed since the build. A missing or unreadable record
means nothing is current; a batch that starts an empty site records the
fingerprint itself. Edition reads the play row before its content. Bites:
keeping the old fingerprint on an empty site, and recording no version.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Generate rewrites only what changed; Rebuild rewrites everything

**Files:**
- Modify: `lib/playcode/export/site_builder.ex`
- Test: `test/playcode/export/site_builder_test.exs` (append; add `alias Playcode.Catalogue`)

**Interfaces:**
- Consumes: `StaticSite.site_changed?/2`, `StaticSite.outdated/1` and `StaticSite.apply_changes/2` (Task 3).
- Produces:
  - `SiteBuilder.generate(opts) :: :started | :queued`, with two possible results:
    - when the site changed, or there is none: `{:site_builder, :done, :generate, {:ok, %{plays: n, size: _, output_dir: _, ...}}}`, as before;
    - otherwise: `{:site_builder, :done, :generate, {:ok, %{changed: count, skipped: [play_id]}}}`.
  - `SiteBuilder.rebuild(opts) :: :started | :queued`. The job is `:rebuild`; its result is always `generate/1`'s, `{:ok, %{plays: n, ...}}`.
  - Progress for a full build is broadcast under the job that runs it: `{:site_builder, :progress, :generate | :rebuild, info}`.
  - `SiteBuilder.status/0` may now show `:rebuild` as the job or in the queue.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/export/site_builder_test.exs`, add `alias Playcode.Catalogue` under the existing aliases, then append before the final `end`:

```elixir
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/playcode/export/site_builder_test.exs`
Expected: FAIL.
- The `changed:` patterns never arrive: Generate still rebuilds everything, so `assert_receive` times out.
- `SiteBuilder.rebuild/1` is undefined.
- The settings test passes already (Generate always rebuilds), so the change itself has to prove it bites (Step 5).

- [ ] **Step 3: Implement**

In `lib/playcode/export/site_builder.ex`:

1. In the `@moduledoc`, change the sentence `a generate or a deploy runs on its own, in its turn. Generate rebuilds the plays on disk when it runs.` to:

```
  a generate, a rebuild or a deploy runs on its own, in its turn. Generate brings the
  site up to date when it runs: every play in it when the site's code or settings
  changed since it was built, only the changed plays otherwise. Rebuild always
  rebuilds every play.
```

Also change `Jobs are `:generate`, `{:batch, ...}` and `:deploy`.` to `Jobs are `:generate`, `:rebuild`, `{:batch, [{:add, play_id} | {:remove, code}]}` and `:deploy`.`, and in the `:queued` list add `:rebuild` after `:generate`.

2. Replace `generate/1`'s `@doc` and add `rebuild/1` after it:

```elixir
  @doc """
  Brings the site up to date. When its code or settings changed since it was built
  (`StaticSite.site_changed?/2`), or there is none, every play in it is rebuilt (every
  complete play if it is empty) and the result is `StaticSite.generate/1`'s. Otherwise
  only the plays that changed are written again and the ones no longer published taken
  out, in one batch, and the result is `{:ok, %{changed: count, skipped: [play_id]}}`.
  `opts` as `StaticSite.generate/1` takes them, but for the directory and plays.
  """
  def generate(opts), do: request(:generate, opts)

  @doc "Rebuilds every play in the site, whatever changed. Results as `generate/1`'s full build."
  def rebuild(opts), do: request(:rebuild, opts)
```

3. Change the first `take/1` clause's guard to `when request in [:generate, :rebuild, :deploy]`.

4. Replace `run(:generate, opts)` with:

```elixir
  defp run(:generate, opts) do
    if StaticSite.site_changed?(StaticSite.output_dir(), opts),
      do: build_all(:generate, opts),
      else: refresh(opts)
  end

  defp run(:rebuild, opts), do: build_all(:rebuild, opts)
```

5. Add these private functions after `run(:deploy, repo)`:

```elixir
  # Rebuilds the site as it stands when the job runs, not when it was asked for: an add
  # or remove queued before it keeps its change.
  defp build_all(job, opts) do
    opts
    |> in_site()
    |> Keyword.put(:play_codes, codes_in_site())
    |> Keyword.put(:on_progress, progress(job))
    |> StaticSite.generate()
  end

  # Only what changed since the last build; with nothing to do, nothing is written.
  defp refresh(opts) do
    case StaticSite.outdated(StaticSite.output_dir()) do
      [] ->
        {:ok, %{changed: 0, skipped: []}}

      changes ->
        {:ok, %{skipped: skipped}} = StaticSite.apply_changes(changes, in_site(opts))
        {:ok, %{changed: length(changes), skipped: skipped}}
    end
  end
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/playcode/export/site_builder_test.exs`
Expected: PASS. That includes the existing "a generate queued behind an add rebuilds the site as it stands when it runs": its site is current, so Generate refreshes and keeps `b`.

- [ ] **Step 5: Prove the tests bite**

1. In `run(:generate, opts)`, replace `else: refresh(opts)` with `else: build_all(:generate, opts)`. Expected: "rewrites only the plays that changed", "with nothing changed writes nothing" and "takes out the plays archived…" fail. Restore it.
2. Replace `if StaticSite.site_changed?(StaticSite.output_dir(), opts),` with `if false,`. Expected: "rebuilds every play when the site's settings changed" fails. Restore it.

- [ ] **Step 6: Run the whole suite, format, compile, commit**

The export page does not handle `:rebuild` yet, and the incremental Generate result. No page test sends either, so the suite stays green; Task 6 adds both.

```bash
mix test
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/site_builder.ex test/playcode/export/site_builder_test.exs
git commit -m "feat: Generate rewrites only the plays that changed; Rebuild rewrites all

Generate rebuilds every play only when the site's fingerprint changed or it has
no build record; otherwise it runs outdated/1 as one batch and writes nothing
when nothing changed. Bites: always rebuilding, and never noticing a settings
change, each turn tests red.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Relay Postgres's notifications to the export page and the play's admin pages

**Files:**
- Create: `lib/playcode/export/play_change_listener.ex`
- Modify: `lib/playcode/application.ex` (`children/0`)
- Modify: `lib/playcode/play_content.ex` (`broadcast_content_changed/1`, the moduledoc)
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex` (its 11 `broadcast_content_changed` calls)
- Modify: `CLAUDE.md` (the "Recompute statistics" line)
- Test: `test/playcode/export/play_change_listener_test.exs`

**Interfaces:**
- Consumes: the `play_changed` channel (Task 1).
- Produces:
  - `{:play_changed, play_id :: String.t()}` on the `"static_site"` PubSub topic, the same topic `SiteBuilder.subscribe/0` joins.
  - `{:play_content_changed, play_id}` on `play_content:<id>`, the topic `PlayContent.subscribe/1` joins, for every writer. The content editor and the play list already handle it.
  - `PlayContent.notify_changed/1` (the broadcast) and `PlayContent.refresh_derived/1` (the verse count and the statistics delete), in place of `broadcast_content_changed/1`.

- [ ] **Step 1: Write the failing test**

Create `test/playcode/export/play_change_listener_test.exs`:

```elixir
defmodule Playcode.Export.PlayChangeListenerTest do
  @moduledoc """
  Postgres's `play_changed` notifications reach the export page's topic. Postgres sends
  one only when its transaction commits, which the sandbox never does, so this test
  commits a real play, outside the sandbox, and purges it again.
  """
  # Not async: while the committed play exists, every other test would see it.
  use Playcode.DataCase, async: false

  import Playcode.TestFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Playcode.Catalogue
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
end
```

- [ ] **Step 2: Run the test to see it fail**

Run: `mix test test/playcode/export/play_change_listener_test.exs`
Expected: FAIL, with `assert_receive` timing out: nothing listens yet.

- [ ] **Step 3: Write the listener and start it**

Create `lib/playcode/export/play_change_listener.ex`:

```elixir
defmodule Playcode.Export.PlayChangeListener do
  @moduledoc """
  Relays the `play_changed` notifications Postgres sends when something a play's static
  pages show changes (migration 20261005120000_track_play_content_version) to the
  `"static_site"` topic as `{:play_changed, play_id}`, so every open export page can
  flag the play at once. Postgres sends them on commit, one per play per transaction.
  """

  # ponytail: a notification sent while the connection is down is lost; the page reads
  # the truth again on mount and after every build.

  use GenServer

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
    {:noreply, conn}
  end
end
```

In `lib/playcode/application.ex`, in `children/0`, right after `Playcode.Export.SiteBuilder,` add:

```elixir
      # Tells the export pages when a play changes, as soon as the edit commits.
      Playcode.Export.PlayChangeListener,
```

- [ ] **Step 4: Run the test to see it pass**

Run: `mix test test/playcode/export/play_change_listener_test.exs`
Expected: PASS.

If `Postgrex.Notifications.start_link/1` rejects an option that `Repo.config()` carries (for example `:pool` in test), keep only the connection options: `Keyword.take(Playcode.Repo.config(), [:hostname, :port, :username, :password, :database, :socket_options, :ssl, :parameters])`. Say so in the commit message.

- [ ] **Step 5: Prove the test bites**

Replace the `Phoenix.PubSub.broadcast(...)` line with `:ok`. Run the test. Expected: it times out. Restore the line.

- [ ] **Step 6: Write the failing test for the play's own topic**

The content editor and the admin play list subscribe to `play_content:<id>` (`PlayContent.subscribe/1`), but only the content editor broadcasts there, through `PlayContent.broadcast_content_changed/1`. A TEI or Word import, the metadata form, character reordering, the FileMaker sync or a mix task leaves both pages stale: an editor open on a re-imported play shows rows that no longer exist, and deleting one raises. The listener sees every writer, so it relays there too.

In `test/playcode/export/play_change_listener_test.exs`:
- Change the alias to `alias Playcode.{Catalogue, PlayContent}`.
- Change the moduledoc's first sentence to: "Postgres's `play_changed` notifications reach the export page's topic and the play's own topic."
- Add after the existing test:

```elixir
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
```

- [ ] **Step 7: Run the test to see it fail**

Run: `mix test test/playcode/export/play_change_listener_test.exs`
Expected: the new test FAILS, with `assert_receive` timing out; the first test still passes.

- [ ] **Step 8: Relay to the play's topic; stop broadcasting by hand**

1. In `lib/playcode/play_content.ex`, replace `broadcast_content_changed/1` with:

```elixir
  @doc """
  Tells the play's subscribers that it changed. `Playcode.Export.PlayChangeListener`
  calls it for every `play_changed` notification from Postgres, so every writer reaches
  them, once its transaction commits.
  """
  def notify_changed(play_id) do
    Phoenix.PubSub.broadcast(@pubsub, topic(play_id), {:play_content_changed, play_id})
  end

  @doc """
  Refreshes what is derived from the content: the verse count and the cached statistics.
  Call it after a content edit. Subscribers hear of the edit from Postgres, on commit.
  """
  def refresh_derived(play_id) do
    Playcode.Catalogue.update_verse_count(play_id)
    Playcode.Statistics.delete_statistics(play_id)
  end
```

   In the same file's moduledoc, replace the paragraph "Broadcasts `{:play_content_changed, play_id}` via PubSub whenever content is mutated, so all subscribed LiveViews can react." with:

```
  Every change to a play reaches `{:play_content_changed, play_id}` on its topic
  (`subscribe/1`) once it commits, whoever made it: Postgres notifies `play_changed`
  and `Playcode.Export.PlayChangeListener` calls `notify_changed/1`.
```

2. In `lib/playcode/export/play_change_listener.ex`, add `alias Playcode.PlayContent`, and in `handle_info/2` add after the `"static_site"` broadcast:

```elixir
    PlayContent.notify_changed(play_id)
```

   Replace its moduledoc with:

```elixir
  @moduledoc """
  Relays the `play_changed` notifications Postgres sends when something a play's static
  pages show changes (migration 20261005120000_track_play_content_version):
  - to `"static_site"` as `{:play_changed, play_id}`, so every open export page can flag
    the play at once;
  - to the play's own topic through `PlayContent.notify_changed/1`, so the content editor
    and the play list reload, whoever made the change.

  Postgres sends them on commit, one per play per transaction.
  """
```

3. Rename the 11 calls in the content editor:

```bash
sed -i 's/PlayContent\.broadcast_content_changed(/PlayContent.refresh_derived(/' lib/playcode_web/live/admin/play_content_editor_live.ex
grep -rn "broadcast_content_changed" lib test
```

   Expected: `grep` prints nothing.

4. In `CLAUDE.md`, in the "Recompute statistics" line, replace "via `broadcast_content_changed/1`" with "via `PlayContent.refresh_derived/1`".

The editing session loses nothing: every editor handler reloads its own assigns directly (`reload_characters()`, `reload_elements()`), and the hand broadcast only reached other sessions. Checked while planning: with the broadcast line removed, the two pages' tests ran 12 tests, 0 failures.

- [ ] **Step 9: Run the tests to see them pass**

Run: `mix test test/playcode/export/play_change_listener_test.exs test/playcode_web/live/admin/play_content_editor_live_test.exs test/playcode_web/live/admin/play_list_live_test.exs`
Expected: PASS.

- [ ] **Step 10: Prove the new test bites**

Delete the `PlayContent.notify_changed(play_id)` line from the listener. Run the listener test. Expected: the new test times out, the first still passes. Restore the line.

- [ ] **Step 11: Run the whole suite, format, compile, commit**

```bash
mix test
mix format
mix compile --warnings-as-errors
git add lib/playcode/export/play_change_listener.ex lib/playcode/application.ex test/playcode/export/play_change_listener_test.exs lib/playcode/play_content.ex lib/playcode_web/live/admin/play_content_editor_live.ex CLAUDE.md
git commit -m "feat: relay play_changed to the export page and the play's own topic

A supervised Postgrex.Notifications connection rebroadcasts each notification
as {:play_changed, play_id} on \"static_site\", and as {:play_content_changed,
play_id} on the play's own topic. The content editor and the play list now
reload after an import, a metadata edit or another admin's change, not only
after the content editor's own. broadcast_content_changed/1 no longer
broadcasts and becomes refresh_derived/1.

The tests commit outside the sandbox and purge what they made. Bite: dropping
either broadcast times its test out.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The export page shows what changed

**Files:**
- Modify: `lib/playcode_web/live/admin/export_site_live.ex`
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po` and `priv/gettext/es/LC_MESSAGES/default.po` (through `mix gettext.extract --merge`, then the Spanish by hand)
- Modify: `CLAUDE.md`
- Test: `test/playcode_web/live/admin/export_site_live_test.exs`

**Interfaces:**
- Consumes:
  - `StaticSite.changed_plays/1` and `StaticSite.site_changed?/2` (Task 3);
  - `SiteBuilder.rebuild/1`, the job `:rebuild`, and the incremental Generate result `{:ok, %{changed: n, skipped: _}}` (Task 4);
  - `{:play_changed, id}` on `"static_site"` (Task 5).
- Produces:
  - the row badge text `gettext("Changed")`;
  - a row button with the text `gettext("Refresh")`;
  - a button "Rebuild everything";
  - the banner `#site-changed`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode_web/live/admin/export_site_live_test.exs`, add `alias Playcode.Catalogue` next to the existing alias. Add these helpers after `wait_for/2`:

```elixir
  defp row(play), do: "#play-#{play.id}"

  # ConnCase's t/2 is gettext/3, which cannot reach a plural entry.
  defp n(singular, plural, count),
    do: Gettext.ngettext(PlaycodeWeb.Gettext, singular, plural, count)
```

Then append, before the final `end`:

```elixir
  describe "changes since the last build" do
    test "a published play edited since is flagged, and Refresh publishes it again",
         %{conn: conn, a: a, b: b} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      refute has_element?(lv, row(a), t("Changed"))

      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert has_element?(lv, row(a), t("Changed"))
      refute has_element?(lv, row(b), t("Changed"))

      assert render(lv) =~
               n(
                 "One published play has changed. Generate refreshes it.",
                 "%{count} published plays have changed. Generate refreshes them.",
                 1
               )

      lv |> element("#{row(a)} button", t("Refresh")) |> render_click()
      wait_for(fn -> render(lv) =~ t("Play exported to static site.") end)

      refute has_element?(lv, row(a), t("Changed"))
      assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "Alpha Revised"
    end

    test "a change announced while the page is open flags the play at once",
         %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      refute has_element?(lv, row(a), t("Changed"))

      # What Playcode.Export.PlayChangeListener sends when the edit commits.
      Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, a.id})
      assert has_element?(lv, row(a), t("Changed"))
    end

    # Review Focus 5.
    test "a change to a play that no longer exists flags nothing", %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      Phoenix.PubSub.broadcast(
        Playcode.PubSub,
        "static_site",
        {:play_changed, Ecto.UUID.generate()}
      )

      refute has_element?(lv, row(a), t("Changed"))
    end

    test "Generate refreshes only the changed plays and says how many", %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})

      lv |> element("form[phx-submit=generate]") |> render_submit()
      wait_for(fn -> render(lv) =~ n("One play refreshed.", "%{count} plays refreshed.", 1) end)

      assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "Alpha Revised"
      refute has_element?(lv, row(a), t("Changed"))
    end

    test "Generate with nothing changed says so", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      assert render(lv) =~ t("Every play in the site is up to date.")

      lv |> element("form[phx-submit=generate]") |> render_submit()
      wait_for(fn -> render(lv) =~ t("Nothing has changed since the last build.") end)
    end

    # Review Focus 4: every page's footer shows the version.
    test "a new version is a change to the whole site: Generate rebuilds every play",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      refute has_element?(lv, "#site-changed")

      lv |> element("form[phx-submit=generate]") |> render_change(%{"version" => "9.9"})
      assert has_element?(lv, "#site-changed")
      assert render(lv) =~ t("Rebuilds the %{count} plays in the site.", count: 2)

      # "Generation Complete" shows only for a full build: starting one hides it first.
      generate(lv)
      refute has_element?(lv, "#site-changed")
    end

    test "Rebuild everything rebuilds the site though nothing changed", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      lv |> element("button", t("Rebuild everything")) |> render_click()
      wait_for(fn -> render(lv) =~ t("Generation Complete") end)
    end
  end
```

Two notes on these tests:
- **Waiting on page text is deterministic here.** `render_submit`/`render_click` return only after the builder answered the page's call, and the builder broadcasts `:started` before it answers. So the page drops the previous "Generation Complete" before the test's next render.
- **The banner is selected by its id.** Its text has an apostrophe, which HEEx escapes, so `render(lv) =~` would not find it.

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/playcode_web/live/admin/export_site_live_test.exs`
Expected: FAIL. There is no "Changed" badge, no Refresh button, no `#site-changed` banner and no "Rebuild everything" button. A `{:play_changed, _}` message crashes the page with a `FunctionClauseError` in `handle_info/2`. An incremental Generate's `:done` crashes `done/3`.

- [ ] **Step 3: Implement the page**

In `lib/playcode_web/live/admin/export_site_live.ex`:

1. In `mount/3`, after `|> assign(:pending, %{})`:

```elixir
      |> assign(:changed, MapSet.new())
      |> assign(:site_changed, false)
```

2. Replace `handle_event("update_form", ...)`, `handle_event("generate", ...)` and the first line of `handle_event("toggle_play", ...)`'s body, and add the two new events:

```elixir
  @impl true
  def handle_event("update_form", params, socket) do
    {:noreply,
     socket
     |> assign(:version, params["version"] || "")
     |> assign(:base_url, params["base_url"] || "/")
     |> assign(:github_repo, params["github_repo"] || "")
     |> track_changes()}
  end

  def handle_event("generate", _params, socket),
    do: socket |> form_opts() |> SiteBuilder.generate() |> queued_flash(socket)

  def handle_event("rebuild", _params, socket),
    do: socket |> form_opts() |> SiteBuilder.rebuild() |> queued_flash(socket)

  # A changed play already in the site: written again, in a batch like any add.
  def handle_event("refresh_play", %{"id" => id}, socket),
    do: id |> SiteBuilder.add(form_opts(socket)) |> queued_flash(socket)
```

In `toggle_play`, replace `opts = [version: socket.assigns.version, base_url: socket.assigns.base_url]` with `opts = form_opts(socket)`.

3. Replace the `:progress, :generate` clause, and add a `:play_changed` clause after the `:failed` one:

```elixir
  def handle_info({:site_builder, :progress, job, info}, socket)
      when job in [:generate, :rebuild] do
    {:noreply,
     socket
     |> assign(:gen_current, info.current)
     |> assign(:gen_total, info.total)
     |> assign(:gen_detail, info.detail)}
  end
```

```elixir
  # Postgres says a play changed (Playcode.Export.PlayChangeListener). Any play: the
  # page reads again which of its plays changed.
  def handle_info({:play_changed, _play_id}, socket), do: {:noreply, track_changes(socket)}
```

4. In `render/1`, make four changes.

   **a. The banner.** Right after the closing `</div>` of the `<div class="mb-6">` header block, add:

```heex
      <div
        :if={@site_changed and MapSet.size(@exported_codes) > 0}
        id="site-changed"
        class="alert alert-warning mb-6"
      >
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>
          {gettext(
            "The site's design or settings changed since the last build. Generate will rebuild every play."
          )}
        </span>
      </div>
```

   **b. The Rebuild button.** Inside `<div class="flex items-center gap-4">`, right after the Generate submit `</button>`, add:

```heex
              <button
                :if={MapSet.size(@exported_codes) > 0}
                type="button"
                phx-click="rebuild"
                class="btn btn-outline"
                disabled={@generating}
              >
                {gettext("Rebuild everything")}
              </button>
```

   **c. The hint.** Replace the body of `<p class="text-xs text-base-content/50">` (the `if MapSet.size(@exported_codes) == 0 ...` expression) with:

```heex
              {generate_hint(@exported_codes, @site_changed, @changed)}
```

   **d. The badge and Refresh button.** In the play row, between the title `<span class="min-w-0 flex-1">…</span>` and the spinner span, add:

```heex
              <span :if={stale?(play, @changed, @pending)} class="badge badge-warning badge-sm">
                {gettext("Changed")}
              </span>
              <button
                :if={stale?(play, @changed, @pending)}
                type="button"
                phx-click="refresh_play"
                phx-value-id={play.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Refresh %{title}", title: play.title)}
              >
                <.icon name="hero-arrow-path-mini" class="size-4" />
                {gettext("Refresh")}
              </button>
```

5. Make `follow/2` and both `finished/2` clauses read the changes again:

```elixir
  defp follow(socket, %{job: job, queue: queue}) do
    queue
    |> Enum.reduce(started(socket, job), &queued(&2, &1))
    |> assign(:exported_codes, on_disk())
    |> track_changes()
  end
```

```elixir
  defp finished(socket, {:batch, changes}),
    do: socket |> settle(changes) |> idle() |> track_changes()

  defp finished(socket, _job),
    do: socket |> assign(:exported_codes, on_disk()) |> idle() |> track_changes()
```

6. Change `defp started(socket, :generate) do` to `defp started(socket, job) when job in [:generate, :rebuild] do`.

7. Replace the two `:generate` clauses of `done/3` (the `{:ok, result}` one and the `{:error, reason}` one) and `failed(:generate, reason)` with:

```elixir
  defp done(socket, job, {:ok, %{plays: plays, size: size} = result})
       when job in [:generate, :rebuild] do
    socket
    |> assign(:gen_result, result)
    |> put_flash(
      :info,
      gettext("Static site generated: %{count} plays (%{size})",
        count: plays,
        size: format_size(size)
      )
    )
  end

  defp done(socket, :generate, {:ok, %{changed: 0}}),
    do: put_flash(socket, :info, gettext("Nothing has changed since the last build."))

  defp done(socket, :generate, {:ok, %{changed: count}}),
    do: put_flash(socket, :info, ngettext("One play refreshed.", "%{count} plays refreshed.", count))
```

```elixir
  defp done(socket, job, {:error, reason}) when job in [:generate, :rebuild],
    do: put_flash(socket, :error, failed(job, inspect(reason)))
```

```elixir
  defp failed(job, reason) when job in [:generate, :rebuild],
    do: gettext("Generation failed: %{reason}", reason: reason)
```

Keep the order of the clauses: the generate and rebuild `done/3` clauses come before the `{:batch, …}` ones, as the old `:generate` clause did.

8. Add the private helpers next to `on_disk/0`:

```elixir
  # The form values every build takes.
  defp form_opts(socket), do: [version: socket.assigns.version, base_url: socket.assigns.base_url]

  # Which published plays changed since they were written, and whether the site as a
  # whole did, for the version in the form.
  defp track_changes(socket) do
    dir = StaticSite.output_dir()

    assign(socket,
      changed: MapSet.new(StaticSite.changed_plays(dir)),
      site_changed: StaticSite.site_changed?(dir, version: socket.assigns.version)
    )
  end

  # Flagged while it differs from its pages and no change of it is on its way.
  defp stale?(play, changed, pending),
    do: MapSet.member?(changed, play.code) and not Map.has_key?(pending, play.id)

  # What Generate will do, under its button.
  defp generate_hint(exported, site_changed?, changed) do
    cond do
      MapSet.size(exported) == 0 ->
        gettext("Builds every complete play.")

      site_changed? ->
        gettext("Rebuilds the %{count} plays in the site.", count: MapSet.size(exported))

      MapSet.size(changed) == 0 ->
        gettext("Every play in the site is up to date.")

      true ->
        ngettext(
          "One published play has changed. Generate refreshes it.",
          "%{count} published plays have changed. Generate refreshes them.",
          MapSet.size(changed)
        )
    end
  end
```

- [ ] **Step 4: Spanish**

Run `mix gettext.extract --merge`. Check every entry it marks `#, fuzzy` in `priv/gettext/es/LC_MESSAGES/default.po`. For the new msgids, remove the `fuzzy` flag and set exactly these translations:

```
msgid "Changed"
msgstr "Modificada"

msgid "Refresh"
msgstr "Actualizar"

msgid "Refresh %{title}"
msgstr "Actualizar %{title}"

msgid "Rebuild everything"
msgstr "Regenerar todo"

msgid "Every play in the site is up to date."
msgstr "Todas las obras del sitio están al día."

msgid "Nothing has changed since the last build."
msgstr "Nada ha cambiado desde la última generación."

msgid "The site's design or settings changed since the last build. Generate will rebuild every play."
msgstr "El diseño o la configuración del sitio han cambiado desde la última generación: al generar se regenerarán todas las obras."

msgid "One published play has changed. Generate refreshes it."
msgid_plural "%{count} published plays have changed. Generate refreshes them."
msgstr[0] "Una obra publicada ha cambiado; al generar se actualizará."
msgstr[1] "%{count} obras publicadas han cambiado; al generar se actualizarán."

msgid "One play refreshed."
msgid_plural "%{count} plays refreshed."
msgstr[0] "Se ha actualizado una obra."
msgstr[1] "Se han actualizado %{count} obras."
```

Leave each entry's `#:` reference and `#, elixir-autogen, elixir-format` comment lines as the extractor wrote them. Leave the English `.po` as extracted. Any *existing* entry that the extractor marked fuzzy and that you did not touch goes back to how it was, minus the flag. The old hint's strings ("Builds every complete play.", "Rebuilds the %{count} plays in the site.") are still used, so keep them.

- [ ] **Step 5: Run the tests to see them pass**

Run: `mix test test/playcode_web/live/admin/export_site_live_test.exs`
Expected: PASS, including every existing test in the file.
- "Generate rebuilds only the plays in the site, so a removed play stays out" still waits for "Generation Complete". Its `build_site/1` builds with version `"1.0"` while the page sends the app's version, so that Generate is a full rebuild.

- [ ] **Step 6: Prove the tests bite**

1. Remove `|> track_changes()` from `finished(socket, {:batch, changes})`. Expected: "a published play edited since is flagged, and Refresh…" fails, because the badge stays. Restore it.
2. Delete the `{:play_changed, _play_id}` clause. Expected: the two `play_changed` tests fail, because the page crashes. Restore it.
3. In `generate_hint/3`, swap the `site_changed?` and `MapSet.size(changed) == 0` branches. Expected: "a new version is a change to the whole site…" fails on the hint. Restore the order.

- [ ] **Step 7: Document**

In `CLAUDE.md`:

1. **Project Structure.** Under `export/`, after the `site_builder.ex` line, add:

```
│       ├── play_change_listener.ex   # Relays Postgres's play_changed notifications to the export page and the play's topic
```

   Under `static_site.ex`'s children, after `search.ex`, add:

```
│           ├── fingerprint.ex        # One hash of the code, assets and settings the pages are built with
```

2. **Database Schema.** After the `plays` has_many bullet, add:

```
- `plays.content_version` - moved by Postgres triggers (migration `20261005120000_track_play_content_version`) whenever anything a play's static pages show changes: its own row, its divisions, elements, speakers, characters, editors, sources, notes and places, the gazetteer entries of those places and their ancestors, and the rows of its original and translations. Once per transaction, with a `pg_notify('play_changed', id)`. Never written by the app (`writable: :never`). **A new table with a `play_id` whose rows appear on a play's pages needs the `play_row_changed()` trigger in its migration** (the migration's moduledoc has the line); `test/playcode/content_version_test.exs` fails until it has it. Adding a column needs nothing. Over-flagging is deliberate: any statement touching a play's rows flags it, even when the values end up the same
```

3. **Static Site Export, Architecture.** After the `Playcode.Export.SiteBuilder` bullet, add:

```
- **Change tracking.** Every build writes `build.json` at the site root: the site fingerprint (`StaticSite.Fingerprint`: the export's code by `module_info(:md5)`, `priv/static_site`, the rendering libraries' versions and the `:version` option) and each published play's `content_version`. `StaticSite.changed_plays/1` lists the published plays whose version moved since, `site_changed?/2` says whether the fingerprint did (or there is no `build.json`), and `outdated/1` is the batch that brings the site up to date. `Playcode.Export.PlayChangeListener` relays Postgres's `play_changed` notifications to `"static_site"`, so the export page flags a changed play, with a Refresh button, as soon as the edit commits, and to the play's own topic (`PlayContent.notify_changed/1`), so the content editor and the play list reload whoever made the change. Generate (`SiteBuilder.generate/1`) rebuilds every play only when the site changed; otherwise it writes the changed plays and takes out the archived or incomplete ones in one batch, and writes nothing when nothing changed. Rebuild everything (`SiteBuilder.rebuild/1`) always rebuilds. `test/playcode/export/static_site/fingerprint_test.exs` fails when the export calls a module of the app that is neither fingerprinted nor data access
```

   In the same section, change the sentence `Generate rebuilds the plays on disk when it runs.` to `Generate brings the plays on disk up to date when it runs.`

4. **Output structure.** Under `_site/`, after the `index.html  search.html  about.html` line, add:

```
├── build.json                 the fingerprint it was built with, and each play's content_version
```

5. **Usage.** Change the Admin UI line to:

```
**Admin UI**: `GET /admin/export` (`PlaycodeWeb.Admin.ExportSiteLive`) — configure version, base URL, GitHub repo; Generate brings the site up to date (only the changed plays, unless the site's code or settings changed), Rebuild everything rebuilds it whole; each changed play shows a Refresh button; download as .zip or deploy to GitHub Pages.
```

6. **What Still Needs To Be Done, Low Priority / Future.** Add:

```
- [ ] **Fly volume for the static site (optional)** - production has no volume, so every app deploy wipes `_site/` and its `build.json`, and the first Generate after a deploy rebuilds every play. A 1 GB volume (about $0.15 a month) mounted at `/data`, with `:static_site_dir` pointed there, would keep incremental builds across deploys. The Postgres volume belongs to the separate database app and cannot be shared
```

- [ ] **Step 8: Run the whole suite, format, compile, commit**

```bash
mix test
node --test test/js/search.test.mjs
mix format
mix compile --warnings-as-errors
git add lib/playcode_web/live/admin/export_site_live.ex test/playcode_web/live/admin/export_site_live_test.exs priv/gettext/default.pot priv/gettext/en/LC_MESSAGES/default.po priv/gettext/es/LC_MESSAGES/default.po CLAUDE.md
git commit -m "feat: the export page flags changed plays and refreshes only them

Each published play edited since it was written shows Changed with a Refresh
button, live through play_changed; a banner says when the site's code or
settings changed; Rebuild everything forces a full build. Spanish added.
Bites: no recompute after a batch, no play_changed clause, and the hint's
branch order each turn a test red.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Fixes found on the way

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex` (`reset_tei_content/1`)
- Modify: `lib/playcode/catalogue.ex` (`get_play_with_all!/2` and `get_play_by_code_with_all!/2`)
- Test: `test/playcode/import/tei_parser_test.exs`, `test/playcode/export/static_site_test.exs`, `test/playcode/export/tei_xml_test.exs`

**Interfaces:**
- Produces:
  - `Catalogue.get_play_with_all!/2` and `get_play_by_code_with_all!/2` return `derived_plays` ordered by `title_sort, title`, `editorial_notes` ordered by `position`, and each `play_places[].place.names` ordered by `position, id`.
  - A TEI re-import leaves no cached statistics.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/import/tei_parser_test.exs`, add `alias Playcode.Statistics` to the aliases, and append before the final `end`:

```elixir
  # The statistics cache outlived a re-import, so the play's statistics kept the old
  # text's numbers.
  test "a re-import replaces the play's statistics" do
    code = "TSTATS#{System.unique_integer([:positive])}"

    body = fn lines ->
      ~s(<div1 type="acto" n="1"><head>ACTO</head><div2 type="escena" n="1"><sp><speaker>A</speaker><lg>#{lines}</lg></sp></div2></div1>)
    end

    {:ok, play} = TeiParser.import_file(write_tmp!(tei(code: code, body: body.(~s(<l n="1">Uno</l>)))))
    assert Statistics.get_statistics(play.id).data["total_verses"] == 1

    {:ok, _} =
      TeiParser.import_file(
        write_tmp!(tei(code: code, body: body.(~s(<l n="1">Uno</l><l n="2">Dos</l>))))
      )

    assert Statistics.get_statistics(play.id).data["total_verses"] == 2
  end
```

In `test/playcode/export/static_site_test.exs`, append before the final `end`:

```elixir
  test "a title page lists the published translations by title, and its notes in their order" do
    original = complete_play(%{"title" => "Original"})

    [zeta, alfa] =
      for title <- ["Zeta", "Alfa"] do
        complete_play(%{
          "title" => title,
          "title_sort" => title,
          "parent_play_id" => original.id,
          "relationship_type" => "traduccion"
        })
      end

    for {heading, position} <- [{"Second note", 2}, {"First note", 1}] do
      {:ok, _} =
        Catalogue.create_play_editorial_note(%{
          play_id: original.id,
          section_type: "nota",
          heading: heading,
          content: "Text",
          position: position
        })
    end

    page = title_page(generate!([original, zeta, alfa]), original)

    assert texts(page, "li a cite") == ["Alfa", "Zeta"]

    assert Enum.filter(texts(page, "h2"), &(&1 in ["First note", "Second note"])) ==
             ["First note", "Second note"]
  end
```

In `test/playcode/export/tei_xml_test.exs`, append before the final `end` (outside the `describe "places"` block):

```elixir
  test "a place's names are exported in their order" do
    place =
      place_fixture(%{
        "names" => [
          %{"name" => "Valentia", "language" => "la", "position" => 2},
          %{"name" => "Valencia", "language" => "es", "is_preferred" => "true", "position" => 1}
        ]
      })

    play = play_fixture()
    play_place_fixture(play, place)
    names = xml_texts(export_tei(play), "placeName")

    assert Enum.find_index(names, &(&1 == "Valencia")) <
             Enum.find_index(names, &(&1 == "Valentia"))
  end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/playcode/import/tei_parser_test.exs test/playcode/export/static_site_test.exs test/playcode/export/tei_xml_test.exs`

Expected failures:
- **The re-import test:** the second assertion fails with `1 == 2`, because the cache kept the old count. If the *first* assertion fails instead, the snippet does not parse as verse. Compare it with the speech in `test/playcode/tei_roundtrip_test.exs`, "a speech keeps its speaker…", and fix the snippet, not the code.
- **The title page test:** the translations come in insertion order (`["Zeta", "Alfa"]`), and the notes by `inserted_at`, which ties within a second ("Second note" first).
- **The TEI test:** "Valentia" comes first.

Postgres returns unordered rows in heap order, which here is insertion order. If either ordering test passes before the fix anyway, say so in the report: it cannot prove it bites, and the fix stands on the TEI export's own position ordering.

- [ ] **Step 3: Implement**

In `lib/playcode/import/tei_parser.ex`, at the end of `reset_tei_content/1`, after `Places.delete_tei_play_places(id)`:

```elixir

    # The cached statistics describe the old text.
    Playcode.Statistics.delete_statistics(id)
```

In `lib/playcode/catalogue.ex`:
- Add `PlaceName` to the places alias: `alias Playcode.Places.{PlaceName, PlayPlace}` in place of `alias Playcode.Places.PlayPlace`.
- Replace both preload lists, in `get_play_with_all!/2` and in `get_play_by_code_with_all!/2`, with a call to one private function:

```elixir
  def get_play_with_all!(id, opts \\ []) do
    Play
    |> scope(opts)
    |> Repo.get!(id)
    |> with_all()
  end

  def get_play_by_code_with_all!(code, opts \\ []) do
    Play
    |> scope(opts)
    |> Repo.get_by!(code: code)
    |> with_all()
  end
```

and, in the `# --- Private ---` section:

```elixir
  # Everything a play's pages show, each list in a fixed order, so the same data always
  # renders the same page.
  defp with_all(play) do
    Repo.preload(play, [
      :statistic,
      :parent_play,
      derived_plays: from(d in Play, order_by: [asc: d.title_sort, asc: d.title]),
      editors: from(e in PlayEditor, order_by: e.position),
      sources: from(s in PlaySource, order_by: s.position),
      editorial_notes: from(n in PlayEditorialNote, order_by: n.position),
      play_places:
        {from(pp in PlayPlace, order_by: pp.position),
         [place: [names: from(n in PlaceName, order_by: [asc: n.position, asc: n.id])]]}
    ])
  end
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/playcode/import/tei_parser_test.exs test/playcode/export/static_site_test.exs test/playcode/export/tei_xml_test.exs`
Expected: PASS.

- [ ] **Step 5: Prove the tests bite**

1. Remove the `Playcode.Statistics.delete_statistics(id)` line. Expected: the re-import test fails. Restore it.
2. Change `editorial_notes: from(n in PlayEditorialNote, order_by: n.position)` to `order_by: [desc: n.position]`. Expected: the title page test fails. Restore it.
3. Change the names' order to `[desc: n.position, asc: n.id]`. Expected: the TEI test fails. Restore it.
4. Change `derived_plays`' order to `[desc: d.title_sort, desc: d.title]`. Expected: the title page test fails. Restore it.

- [ ] **Step 6: Run the whole suite, including the slow sweep, then format, compile, commit**

The place-name order reaches every TEI export. `--include slow` adds the corpus round trip, a few minutes.

```bash
mix test --include slow
mix format
mix compile --warnings-as-errors
git add lib/playcode/import/tei_parser.ex lib/playcode/catalogue.ex test/playcode/import/tei_parser_test.exs test/playcode/export/static_site_test.exs test/playcode/export/tei_xml_test.exs
git commit -m "fix: a TEI re-import drops cached statistics; a play's lists keep one order

The statistics cache outlived a re-import. get_play_with_all! loaded
translations, notes and place names in heap order, so the same data could
render a different page. Bites: removing the delete, and reversing each order.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## After the last task

- `mix test --include slow` and `node --test test/js/search.test.mjs` are green.
- The branch has seven commits, one per task.
- **Leave the dev database and the merge to the user.** Running `mix ecto.migrate` adds the column and triggers to `playcode_dev`, and every existing play gets a version. A site built before then has no `build.json`, so the first Generate after the migration rebuilds everything, as designed.
