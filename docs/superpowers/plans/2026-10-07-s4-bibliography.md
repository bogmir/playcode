# S4 Bibliography Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every play a bibliography (modern editions, criticism, translations, adaptations) made of corpus-wide entries, imported once from FileMaker, edited on its own admin tab, and shown on `/plays/:code`, on the static site and in the TEI export.

**Architecture:** Two tables: `bibliography_entries` (shared, one row per work cited) and `play_bibliography` (a play's link to an entry, carrying that play's volume, pages and internal note). The context is `Playcode.Bibliography`, and one renderer, `Playcode.Bibliography.Citation`, prints an entry for every surface. A one-time import reads six FMPXMLRESULT tables through `Playcode.Import.FilemakerXml` and `Playcode.Import.Bibliography`.

**Tech Stack:** Elixir 1.19, Phoenix 1.8 LiveView, Ecto/PostgreSQL (UUID keys, plpgsql triggers), Saxy, XmlBuilder, DaisyUI/Tailwind, gettext.

**Spec:** `docs/superpowers/specs/2026-10-07-s4-bibliography-design.md`. Read it before starting: the plan argues from it. Research behind it: `docs/superpowers/specs/2026-09-25-s4-bibliography-research.md`.

## Global Constraints

- **Run mix plainly** (`mix test`, `mix format`). Never prefix a command with `export PATH=…`.
- **Every task is red, green, refactor.**
  - Write the failing test, run it and see it fail for the expected reason, write the least code that passes, run it green.
  - Then refactor while green, `mix format`, `mix compile --warnings-as-errors`, and the whole `mix test`, before committing.
- **Test through the outermost API** (CLAUDE.md):
  - LiveViews with `live/2`, `form/3` and `render_submit/1`.
  - Mix tasks with `Mix.Task.rerun/2`.
  - Read back through `Playcode.Bibliography`, never `Repo`.
  - Select elements by visible text, by a stable `id`, or by the `aria-label` of an icon-only button.
- **Prove a new test bites.** A test written for code that already works must be shown red once: break the line it covers, run it, put the line back. Say so in the commit message.
- **Commit only your own files, by explicit path:** `git commit -- path1 path2`. The working tree holds the user's unrelated work in progress (`CLAUDE.md`, `lib/playcode/export/tei_xml.ex`, `lib/playcode/import/tei_parser.ex`, `lib/playcode/play_content/element.ex`, `test/playcode/tei_roundtrip_test.exs` at the time of writing). Never `git add -A`, never `git commit -a`.
  - Before Task 10, run `git status`. If `tei_xml.ex` still has uncommitted changes that are not yours, stop and ask.
- **Commit messages end with:** `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- **No new dependencies.**
- **Every new user-visible string gets Spanish:**
  - `mix gettext.extract --merge`, then fill the `msgstr` in `priv/gettext/es/LC_MESSAGES/default.po`.
  - Check every entry it marks `fuzzy`: it fuzzy-matches unrelated strings.
  - Custom changeset messages go by hand into `priv/gettext/errors.pot` and `priv/gettext/es/LC_MESSAGES/errors.po`.
- **Citation labels are FileMaker's and are not translated:** `Ed.`, `Tra.`, `In:`, `Vol.`, `vols.`, `p.`, `pp.`, `Orig:`, `URL:`, `acc.`.
- **`note` (entry) and `note` (link) are for researchers only.** They never appear on `/plays/:code`, on the static site or in the TEI export. `public_note` is printed.
- **A new table with a `play_id`** needs the `play_row_changed()` trigger (`test/playcode/content_version_test.exs` enforces it).
- **A new gated route** needs a row in `test/playcode_web/authorization_test.exs`.
- **Static site budgets:**
  - `priv/static_site/style.css` stays under 25 KB; it is 16.0 KB today.
  - No third-party requests.

## Review Focus

The inputs most likely to bite a real user that the spec implies but does not spell out:

1. **HTML or a script typed into any field** comes out escaped on every surface, and only `http(s)` addresses become links. Pinned in Task 2.
2. **The admin filter ignores accents and case** (`zuniga` finds `Zúñiga`) and says when nothing matches. Pinned in Task 7.
3. **A search term containing `%` or `_`** matches literally, and a blank term lists nothing rather than the whole corpus. Pinned in Task 1.
4. **A field holding only spaces counts as empty:** an entry whose only "title" is spaces is refused. Pinned in Task 1.
5. **A FileMaker URL with junk in front** (`. http://…`, found in the dump) prints as text, not a broken link, and is left out of TEI's `<ptr>` so the file still validates. Pinned in Tasks 2 and 10.

---

## File map

| File | Responsibility |
|---|---|
| `priv/repo/migrations/20261007120000_create_bibliography.exs` | Both tables, indexes, the two change-tracking triggers |
| `lib/playcode/bibliography.ex` | The context: CRUD, grouping and order, search, folding |
| `lib/playcode/bibliography/entry.ex` | Shared entry schema, vocabularies, `named?/1` |
| `lib/playcode/bibliography/link.ex` | A play's link to an entry |
| `lib/playcode/bibliography/citation.ex` | The one renderer: segments, plain text, safe HTML |
| `lib/playcode/import/filemaker_xml.ex` | FMPXMLRESULT reader |
| `lib/playcode/import/bibliography.ex` | The one-time import: load, plan, apply, report, field mapping |
| `lib/mix/tasks/playcode.import.bibliography.ex` | Mix entry point |
| `lib/playcode/release.ex` | `import_bibliography/2` for Fly |
| `lib/playcode_web/live/admin/play_bibliography_live.ex` | The admin tab |
| `lib/playcode_web/play_labels.ex` | Kind, type and language labels |
| `lib/playcode_web/live/play_show_live.ex` | `#meta-bibliography` and its sidebar entry |
| `lib/playcode/export/static_site/{edition,components}.ex`, `pages/title.html.heex`, `fingerprint.ex`, `priv/static_site/style.css` | Static site section, rail entry, fingerprint |
| `lib/playcode/export/tei_xml.ex` | `<back><div type="bibliografia">` |
| `test/support/citation_oracle.ex` | The FileMaker word-coverage check |
| `test/fixtures/filemaker/ctce_dades/*.xml` | Hand-written six-table dump, one case per import rule |
| `test/fixtures/filemaker/oracle/*.xml`, `regenerate.exs` | 30 records and 16 links cut from the real dump |

---

### Task 1: The model — tables, triggers, context

**Files:**
- Create: `priv/repo/migrations/20261007120000_create_bibliography.exs`
- Create: `lib/playcode/bibliography/entry.ex`, `lib/playcode/bibliography/link.ex`, `lib/playcode/bibliography.ex`
- Modify: `lib/playcode/activity_log/entry.ex:9` (resource types), `lib/playcode_web/live/admin/activity_log_live.ex:117-128` (their labels)
- Modify: `lib/playcode/catalogue/play.ex:69-76` (a name for `de`)
- Modify: `test/support/fixtures.ex` (add `bibliography_fixture/3`)
- Modify: `priv/gettext/errors.pot`, `priv/gettext/es/LC_MESSAGES/errors.po`
- Test: `test/playcode/bibliography_test.exs` (create), `test/playcode/content_version_test.exs`

**Interfaces:**
- Produces:
  - **`Playcode.Bibliography.Entry`:** `kinds/0` (`~w(modern_edition criticism translation adaptation)`, also the display order), `pub_types/0`, `languages/0` (`~w(es en fr it pt de)`), `changeset/2`, `named?/1` (map or struct → boolean).
  - **`Playcode.Bibliography.Link`:** `changeset/2`. It casts only `volume`, `pages` and `note`; `play_id`, `entry_id` and `origin` are set on the struct.
  - **`Playcode.Bibliography` reads:**
    - `get_entry!/1`
    - `get_link!/1` (entry preloaded)
    - `list_links(play_id)` (entries preloaded, in insertion order)
    - `plays_for_entry(entry_id)` → `[%{id, code, title}]` by code
    - `link_counts([entry_id])` → `%{entry_id => n}`
    - `search_entries(term, play_id, limit \\ 10)` → entries not on that play
  - **`Playcode.Bibliography` writes:**
    - `create_entry_for_play(play_id, entry_attrs, link_attrs \\ %{})` → `{:ok, %Link{entry: %Entry{}}}`
    - `link_entry(play_id, entry_id, attrs \\ %{})`
    - `update_entry/2`, `update_link/2`
    - `unlink(link)` → `{:ok, :unlinked | :deleted}`
  - **`Playcode.Bibliography` forms:** `change_entry/2`, `change_link/2`.
  - **`Playcode.TestFixtures.bibliography_fixture(play, entry_attrs \\ %{}, link_attrs \\ %{})`** → the link, entry loaded. Default entry: criticism, book, `monogr_author` "Autor, Ana", a unique `monogr_title`.

- [ ] **Step 1: Write the failing tests**

Create `test/playcode/bibliography_test.exs`:

```elixir
defmodule Playcode.BibliographyTest do
  @moduledoc """
  The corpus-wide bibliography: entries shared by every play that cites them, read back
  through `Playcode.Bibliography`. Spec: docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Bibliography

  describe "entries and links" do
    test "an entry needs an author, an editor or a title" do
      play = play_fixture()

      assert {:error, changeset} =
               Bibliography.create_entry_for_play(play.id, %{
                 "kind" => "criticism",
                 "year_text" => "2005"
               })

      assert "needs an author, an editor or a title" in errors_on(changeset).monogr_title

      # Editions 273 and 420 in FileMaker have editors and no title, and are printed.
      assert {:ok, _} =
               Bibliography.create_entry_for_play(play.id, %{
                 "kind" => "modern_edition",
                 "monogr_editors" => "Herford, C. H."
               })
    end

    test "a title of spaces is no title" do
      play = play_fixture()

      assert {:error, changeset} =
               Bibliography.create_entry_for_play(play.id, %{
                 "kind" => "criticism",
                 "monogr_title" => "   "
               })

      assert "needs an author, an editor or a title" in errors_on(changeset).monogr_title
    end

    test "kind, type and language come from their lists" do
      play = play_fixture()

      {:error, changeset} =
        Bibliography.create_entry_for_play(play.id, %{
          "kind" => "review",
          "pub_type" => "poster",
          "language" => "xx",
          "monogr_title" => "T"
        })

      errors = errors_on(changeset)
      assert errors.kind == ["is invalid"]
      assert errors.pub_type == ["is invalid"]
      assert errors.language == ["is invalid"]
    end

    test "an edit to a shared entry shows on every play that has it" do
      hamlet = play_fixture()
      antony = play_fixture()
      link = bibliography_fixture(hamlet, %{"monogr_title" => "Complete Works"})
      {:ok, _} = Bibliography.link_entry(antony.id, link.entry_id)

      {:ok, _} =
        Bibliography.update_entry(Bibliography.get_entry!(link.entry_id), %{"year_text" => "1986"})

      for play <- [hamlet, antony] do
        assert [%{entry: %{year_text: "1986"}}] = Bibliography.list_links(play.id)
      end

      assert Enum.map(Bibliography.plays_for_entry(link.entry_id), & &1.code) ==
               Enum.sort([hamlet.code, antony.code])

      assert Bibliography.link_counts([link.entry_id]) == %{link.entry_id => 2}
    end

    test "the link holds what belongs to one play" do
      hamlet = play_fixture()
      antony = play_fixture()

      link =
        bibliography_fixture(hamlet, %{"kind" => "modern_edition", "monogr_title" => "Works"}, %{
          "volume" => "5",
          "pages" => "1-100"
        })

      {:ok, other} = Bibliography.link_entry(antony.id, link.entry_id, %{"volume" => "7"})
      {:ok, _} = Bibliography.update_link(other, %{"pages" => "200-300"})

      assert [%{volume: "5", pages: "1-100"}] = Bibliography.list_links(hamlet.id)
      assert [%{volume: "7", pages: "200-300"}] = Bibliography.list_links(antony.id)
    end

    test "a play links an entry only once" do
      play = play_fixture()
      link = bibliography_fixture(play)

      assert {:error, changeset} = Bibliography.link_entry(play.id, link.entry_id)
      assert "is already linked to this play" in errors_on(changeset).entry_id
    end

    test "removing an entry from its last play deletes it" do
      hamlet = play_fixture()
      antony = play_fixture()
      link = bibliography_fixture(hamlet, %{"monogr_title" => "Shared volume"})
      {:ok, other} = Bibliography.link_entry(antony.id, link.entry_id)

      assert {:ok, :unlinked} = Bibliography.unlink(link)
      assert Enum.map(Bibliography.search_entries("Shared volume", hamlet.id), & &1.id) ==
               [link.entry_id]

      assert {:ok, :deleted} = Bibliography.unlink(other)
      assert Bibliography.search_entries("Shared volume", hamlet.id) == []
    end
  end

  describe "search_entries/3" do
    test "finds entries by author, editor or title, leaving out the play's own" do
      hamlet = play_fixture()
      antony = play_fixture()
      bibliography_fixture(hamlet, %{"monogr_title" => "Shakespeare Survey"})

      other =
        bibliography_fixture(antony, %{
          "monogr_title" => "The Riverside Shakespeare",
          "monogr_editors" => "Evans, G. Blakemore"
        })

      assert Enum.map(Bibliography.search_entries("shakespeare", hamlet.id), & &1.id) ==
               [other.entry_id]

      assert Enum.map(Bibliography.search_entries("evans", hamlet.id), & &1.id) ==
               [other.entry_id]
    end

    test "% and _ match themselves, and a blank term finds nothing" do
      play = play_fixture()
      wanted = bibliography_fixture(play_fixture(), %{"monogr_title" => "100% Shakespeare"})
      bibliography_fixture(play_fixture(), %{"monogr_title" => "1000 Plays"})

      assert Enum.map(Bibliography.search_entries("100%", play.id), & &1.id) ==
               [wanted.entry_id]

      assert Bibliography.search_entries("", play.id) == []
      assert Bibliography.search_entries("  ", play.id) == []
      assert Bibliography.search_entries("%", play.id) == []
    end
  end
end
```

Note: `"100%"` becomes the pattern `%100%`, which matches `100% Shakespeare` but also `1000 Plays`. The test expects only the first, so the implementation must escape `%` and `_` for `ILIKE` rather than strip them.

In `test/playcode/content_version_test.exs`:

1. Add `Bibliography` to the alias line: `alias Playcode.{Bibliography, Catalogue, PlayContent, Places, Statistics}`.
2. Add this edit to the `edits` list of "every edit to the text, cast, credits, notes or places moves the play", after `place:`:

```elixir
      bibliography: fn -> bibliography_fixture(play) end,
```

3. Add a test after the places test:

```elixir
  test "an edit to a bibliography entry moves every play that cites it" do
    hamlet = play_fixture()
    antony = play_fixture()
    elsewhere = play_fixture()
    link = bibliography_fixture(hamlet, %{"monogr_title" => "Works"})
    {:ok, _} = Bibliography.link_entry(antony.id, link.entry_id)
    bibliography_fixture(elsewhere)

    # A new value each time: an update that changes nothing sends no UPDATE at all.
    edit = fn ->
      Bibliography.update_entry(Bibliography.get_entry!(link.entry_id), %{
        "year_text" => "#{System.unique_integer([:positive])}"
      })
    end

    assert moves?(hamlet, edit)
    assert moves?(antony, edit)
    refute moves?(elsewhere, edit)
  end
```

In `test/support/fixtures.ex`, add at the end of the module:

```elixir
  def bibliography_fixture(play, entry_attrs \\ %{}, link_attrs \\ %{}) do
    entry_attrs =
      Map.merge(
        %{
          "kind" => "criticism",
          "pub_type" => "book",
          "monogr_author" => "Autor, Ana",
          "monogr_title" => "Libro #{System.unique_integer([:positive])}"
        },
        entry_attrs
      )

    {:ok, link} = Playcode.Bibliography.create_entry_for_play(play.id, entry_attrs, link_attrs)
    link
  end
```

- [ ] **Step 2: Run the tests and see them fail**

Run: `mix test test/playcode/bibliography_test.exs test/playcode/content_version_test.exs`
Expected: compile error, `module Playcode.Bibliography is not available` (or `undefined function bibliography_fixture`).

- [ ] **Step 3: Write the migration**

`priv/repo/migrations/20261007120000_create_bibliography.exs`:

```elixir
defmodule Playcode.Repo.Migrations.CreateBibliography do
  @moduledoc """
  S4: the corpus-wide bibliography and each play's links to it. Spec:
  docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  An entry is shared, so an edit to it must move every play that cites it: that is
  `bibliography_entry_changed()`, on the model of `place_changed()` in
  20261005120000_track_play_content_version.exs. Deleting an entry cascades to its links,
  and the cascade fires the links' own trigger.
  """
  use Ecto.Migration

  def change do
    create table(:bibliography_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :pub_type, :string
      add :language, :string

      for column <- ~w(analytic_author analytic_title analytic_editors analytic_translators
                       monogr_author monogr_title monogr_editors monogr_translators
                       original_title edition volume volumes_total issue pages
                       pub_place publisher year_text url url_accessed_on
                       series siglum public_note note)a do
        add column, :text
      end

      add :filemaker_id, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bibliography_entries, [:filemaker_id],
             where: "filemaker_id IS NOT NULL"
           )

    create table(:play_bibliography, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false

      add :entry_id,
          references(:bibliography_entries, type: :binary_id, on_delete: :delete_all),
          null: false

      add :volume, :text
      add :pages, :text
      add :note, :text
      add :origin, :string, null: false, default: "manual"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:play_bibliography, [:play_id, :entry_id])
    create index(:play_bibliography, [:entry_id])

    execute "CREATE TRIGGER play_bibliography_touch_play AFTER INSERT OR UPDATE OR DELETE ON play_bibliography FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
            "DROP TRIGGER play_bibliography_touch_play ON play_bibliography"

    execute """
            CREATE FUNCTION bibliography_entry_changed() RETURNS trigger AS $$
            BEGIN
              PERFORM touch_play(play_id) FROM play_bibliography WHERE entry_id = NEW.id;
              RETURN NULL;
            END
            $$ LANGUAGE plpgsql
            """,
            "DROP FUNCTION bibliography_entry_changed()"

    # A new entry has no plays yet; a deleted one takes its links with it.
    execute "CREATE TRIGGER bibliography_entries_touch_plays AFTER UPDATE ON bibliography_entries FOR EACH ROW EXECUTE FUNCTION bibliography_entry_changed()",
            "DROP TRIGGER bibliography_entries_touch_plays ON bibliography_entries"
  end
end
```

- [ ] **Step 4: Write the schemas**

`lib/playcode/bibliography/entry.ex`:

```elixir
defmodule Playcode.Bibliography.Entry do
  @moduledoc """
  One work cited, shared by every play that cites it, so one correction reaches them all.

  Two levels, as in TEI's `biblStruct` and FileMaker's own record: `analytic_*` is the
  article, chapter or section; `monogr_*` the book or journal it is in. A book alone fills
  only `monogr_*`. `note` is for researchers only (the project's answer, 2026-10-07);
  `public_note` is printed with the citation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  # Also the order a play's bibliography is shown in.
  @kinds ~w(modern_edition criticism translation adaptation)

  @pub_types ~w(article book_section scholarly_edition book proceedings prologue festschrift
                electronic thesis collection)

  @languages ~w(es en fr it pt de)

  # An entry names something when one of these is filled.
  @names [
    :analytic_author,
    :analytic_title,
    :analytic_editors,
    :monogr_author,
    :monogr_title,
    :monogr_editors
  ]

  @fields [
    :kind,
    :pub_type,
    :language,
    :analytic_author,
    :analytic_title,
    :analytic_editors,
    :analytic_translators,
    :monogr_author,
    :monogr_title,
    :monogr_editors,
    :monogr_translators,
    :original_title,
    :edition,
    :volume,
    :volumes_total,
    :issue,
    :pages,
    :pub_place,
    :publisher,
    :year_text,
    :url,
    :url_accessed_on,
    :series,
    :siglum,
    :public_note,
    :note
  ]

  def kinds, do: @kinds
  def pub_types, do: @pub_types
  def languages, do: @languages

  schema "bibliography_entries" do
    field :kind, :string
    field :pub_type, :string
    field :language, :string
    field :analytic_author, :string
    field :analytic_title, :string
    field :analytic_editors, :string
    field :analytic_translators, :string
    field :monogr_author, :string
    field :monogr_title, :string
    field :monogr_editors, :string
    field :monogr_translators, :string
    field :original_title, :string
    field :edition, :string
    field :volume, :string
    field :volumes_total, :string
    field :issue, :string
    field :pages, :string
    field :pub_place, :string
    field :publisher, :string
    field :year_text, :string
    field :url, :string
    field :url_accessed_on, :string
    field :series, :string
    field :siglum, :string
    field :public_note, :string
    field :note, :string
    field :filemaker_id, :string

    has_many :links, Playcode.Bibliography.Link

    timestamps(type: :utc_datetime)
  end

  @doc "What a form may set. `filemaker_id` is set only by the import, on the struct."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @fields)
    |> validate_required([:kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:pub_type, @pub_types)
    |> validate_inclusion(:language, @languages)
    |> validate_named()
    |> unique_constraint(:filemaker_id)
  end

  @doc "Whether `entry` (an entry or a map with atom keys) has an author, an editor or a title."
  def named?(entry), do: Enum.any?(@names, &(entry |> Map.get(&1) |> present?()))

  defp validate_named(changeset) do
    if changeset |> apply_changes() |> named?(),
      do: changeset,
      else: add_error(changeset, :monogr_title, "needs an author, an editor or a title")
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
```

`lib/playcode/bibliography/link.ex`:

```elixir
defmodule Playcode.Bibliography.Link do
  @moduledoc """
  A play's link to a bibliography entry, with what belongs to that play alone: where it
  sits in a modern edition (`volume`, `pages`) and a `note` for researchers.

  `origin` is `"filemaker"` on a link the import made, which is how a re-run of the import
  knows the play is done, and `"manual"` otherwise.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_bibliography" do
    field :volume, :string
    field :pages, :string
    field :note, :string
    field :origin, :string, default: "manual"

    belongs_to :play, Playcode.Catalogue.Play
    belongs_to :entry, Playcode.Bibliography.Entry

    timestamps(type: :utc_datetime)
  end

  @doc "What a form may set. The play, the entry and `origin` are set on the struct."
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:volume, :pages, :note])
    |> unique_constraint([:play_id, :entry_id],
      error_key: :entry_id,
      message: "is already linked to this play"
    )
    |> foreign_key_constraint(:entry_id)
    |> foreign_key_constraint(:play_id)
  end
end
```

- [ ] **Step 5: Write the context**

`lib/playcode/bibliography.ex`:

```elixir
defmodule Playcode.Bibliography do
  @moduledoc """
  The corpus-wide bibliography (S4): entries shared by every play that cites them, and
  each play's links to them. Spec: docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  An entry lives as long as some play links to it: `unlink/1` deletes it with its last
  link, so there are never orphans to find.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.Catalogue.Play
  alias Playcode.Repo

  @searched [
    :analytic_author,
    :analytic_title,
    :analytic_editors,
    :monogr_author,
    :monogr_title,
    :monogr_editors
  ]

  def change_entry(%Entry{} = entry, attrs \\ %{}), do: Entry.changeset(entry, attrs)
  def change_link(%Link{} = link, attrs \\ %{}), do: Link.changeset(link, attrs)

  def get_entry!(id), do: Repo.get!(Entry, id)
  def get_link!(id), do: Link |> Repo.get!(id) |> Repo.preload(:entry)

  @doc "The play's links with their entries, in the order they were added."
  def list_links(play_id) do
    Link
    |> where([l], l.play_id == ^play_id)
    |> order_by([l], asc: l.inserted_at, asc: l.id)
    |> preload(:entry)
    |> Repo.all()
  end

  @doc "A new entry and the play's link to it, in one transaction. Returns the link, entry loaded."
  def create_entry_for_play(play_id, entry_attrs, link_attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:entry, Entry.changeset(%Entry{}, entry_attrs))
    |> Multi.insert(:link, fn %{entry: entry} ->
      Link.changeset(%Link{play_id: play_id, entry_id: entry.id}, link_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{entry: entry, link: link}} -> {:ok, %{link | entry: entry}}
      {:error, _step, changeset, _done} -> {:error, changeset}
    end
  end

  @doc "Links an entry another play already has."
  def link_entry(play_id, entry_id, attrs \\ %{}) do
    %Link{play_id: play_id, entry_id: entry_id}
    |> Link.changeset(attrs)
    |> Repo.insert()
  end

  def update_entry(%Entry{} = entry, attrs), do: entry |> Entry.changeset(attrs) |> Repo.update()
  def update_link(%Link{} = link, attrs), do: link |> Link.changeset(attrs) |> Repo.update()

  @doc """
  Removes a play's link. `{:ok, :deleted}` when it was the entry's last, which goes with
  it; `{:ok, :unlinked}` otherwise.
  """
  # ponytail: two curators removing an entry's last two links in the same instant can each
  # still see the other's and leave an orphan; lock the entry row if that ever happens.
  def unlink(%Link{} = link) do
    Repo.transaction(fn ->
      Repo.delete!(link)

      if Repo.exists?(from l in Link, where: l.entry_id == ^link.entry_id) do
        :unlinked
      else
        Repo.delete_all(from e in Entry, where: e.id == ^link.entry_id)
        :deleted
      end
    end)
  end

  @doc "Every play linked to an entry, archived ones included, by code."
  def plays_for_entry(entry_id) do
    Play
    |> join(:inner, [p], l in Link, on: l.play_id == p.id)
    |> where([_p, l], l.entry_id == ^entry_id)
    |> order_by([p], p.code)
    |> select([p], %{id: p.id, code: p.code, title: p.title})
    |> Repo.all()
  end

  @doc "How many plays link each entry: `%{entry_id => count}`."
  def link_counts([]), do: %{}

  def link_counts(entry_ids) do
    Link
    |> where([l], l.entry_id in ^entry_ids)
    |> group_by([l], l.entry_id)
    |> select([l], {l.entry_id, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Entries whose authors, editors or titles contain `term`, leaving out those `play_id`
  already has. `%` and `_` match themselves; a blank term finds nothing.
  """
  def search_entries(term, play_id, limit \\ 10) do
    case term |> to_string() |> String.trim() |> String.replace(["%", "_"], "") do
      "" -> []
      _ -> do_search(String.trim(term), play_id, limit)
    end
  end

  defp do_search(term, play_id, limit) do
    pattern = "%" <> String.replace(term, ~r/([\\%_])/, "\\\\\\1") <> "%"
    on_play = from l in Link, where: l.play_id == ^play_id, select: l.entry_id

    matches =
      Enum.reduce(@searched, dynamic(false), fn field, acc ->
        dynamic([e], ^acc or ilike(field(e, ^field), ^pattern))
      end)

    Entry
    |> where([e], e.id not in subquery(on_play))
    |> where(^matches)
    |> order_by([e], asc: e.monogr_title, asc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end
end
```

The escape replaces each `\`, `%` and `_` with a backslash before it. Postgres `ILIKE`'s default escape character is `\`, so `100\%` matches the text `100%`.

- [ ] **Step 6: Activity log, language name, error translation**

- **`lib/playcode/activity_log/entry.ex:9`:** append `bibliography_entry play_bibliography` to `@resource_types`.
- **`lib/playcode_web/live/admin/activity_log_live.ex`:** in `translate_resource_type/1`, before `other -> other`:

```elixir
      "bibliography_entry" -> gettext("bibliography entry")
      "play_bibliography" -> gettext("bibliography link")
```

- **`lib/playcode/catalogue/play.ex`:** add `"de" => "Deutsch"` to `@language_names`. Do not touch `@valid_languages`: German is a bibliography language, not a play language.
- **`priv/gettext/errors.pot`:** append

```
msgid "needs an author, an editor or a title"
msgstr ""
```

  and to `priv/gettext/es/LC_MESSAGES/errors.po`:

```
msgid "needs an author, an editor or a title"
msgstr "necesita un autor, un editor o un título"
```

- [ ] **Step 7: Migrate and run the tests**

Run: `mix ecto.migrate && mix test test/playcode/bibliography_test.exs test/playcode/content_version_test.exs`
Expected: all pass. If `% and _ match themselves` fails, check the escape: print `pattern` and confirm it reads `%100\%%`.

- [ ] **Step 8: Prove the trigger test bites**

1. Comment out the `bibliography_entries_touch_plays` execute in the migration.
2. Run `mix ecto.rollback --step 1 && mix ecto.migrate && mix test test/playcode/content_version_test.exs`.
3. Expected: "an edit to a bibliography entry moves every play that cites it" fails.
4. Restore the line, then roll back and migrate again.

- [ ] **Step 9: Refactor while green, then the full gate**

Look for duplication between `named?/1` and the search fields: both are the six author, editor and title fields. Keep them separate if merging makes either harder to read. Then run `mix format && mix compile --warnings-as-errors && mix test`.
Expected: all green, including `error_translations_test.exs`, which fails if the Spanish errors entry is missing.

- [ ] **Step 10: Commit**

```bash
git add priv/repo/migrations/20261007120000_create_bibliography.exs lib/playcode/bibliography.ex lib/playcode/bibliography/entry.ex lib/playcode/bibliography/link.ex test/playcode/bibliography_test.exs
git commit -m "feat(bibliography): shared entries linked to plays

Entries are corpus-wide so one correction reaches every play (the project's
answer, 2026-10-07). Removing an entry's last link deletes it. Both tables
move the plays they show on: the link by play_row_changed(), an entry edit
by a new bibliography_entry_changed(). The entry trigger test was seen red
with the trigger removed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- priv/repo/migrations/20261007120000_create_bibliography.exs lib/playcode/bibliography.ex lib/playcode/bibliography/entry.ex lib/playcode/bibliography/link.ex test/playcode/bibliography_test.exs test/playcode/content_version_test.exs test/support/fixtures.ex lib/playcode/activity_log/entry.ex lib/playcode_web/live/admin/activity_log_live.ex lib/playcode/catalogue/play.ex priv/gettext/errors.pot priv/gettext/es/LC_MESSAGES/errors.po
```

---

### Task 2: The renderer

**Files:**
- Create: `lib/playcode/bibliography/citation.ex`
- Test: `test/playcode/bibliography/citation_test.exs`

**Interfaces:**
- Consumes: `%Entry{}`, `%Link{}` (Task 1), `Playcode.PlayContent.InlineMarkup.parts/1`.
- Produces:
  - **`Citation.parts(entry, link \\ nil)`:** `[%{text: binary, italic: boolean} | %{url: binary, href: binary | nil}]`. `href` is the URL only when it is `http(s)://…`.
  - **`Citation.plain(entry, link \\ nil)`:** binary.
  - **`Citation.html(entry, link \\ nil)`:** `{:safe, iodata}`, everything escaped.

The order of elements is the spec's "Display" section. Summary:
- **Bibliography:** lead, then edition, then imprint (an article: `Year, vol, issue, p. pages.`; anything else: `Vol. N.` then `Place: Publisher, Year, p. pages, N vols.`), then series, `(Orig: …)`, the public note, `URL: …`.
- **Modern editions:** each level is `Editors, ed. <<Title>>. Author. Tra. …`, with `In:` between levels and `pp.` for pages.

- [ ] **Step 1: Write the failing tests**

`test/playcode/bibliography/citation_test.exs`:

```elixir
defmodule Playcode.Bibliography.CitationTest do
  @moduledoc """
  How an entry is printed: one example per shape pins the order, labels and punctuation.
  test/playcode/bibliography/oracle_test.exs checks against FileMaker's own citations that
  nothing FileMaker printed is left out.
  """
  use ExUnit.Case, async: true

  alias Playcode.Bibliography.{Citation, Entry, Link}

  defp entry(attrs), do: struct(Entry, attrs)
  defp italics(parts), do: for(%{italic: true, text: text} <- parts, do: text)

  test "an article: author, quoted title, journal, then year, volume, issue and pages" do
    article =
      entry(
        kind: "criticism",
        pub_type: "article",
        analytic_author: "Barnett, Timothy Brian",
        analytic_title: "Lope and Tasso",
        monogr_author: "Not printed for a journal",
        monogr_title: "Bulletin of the Comediantes",
        year_text: "2005",
        volume: "57",
        issue: "2",
        pages: "238-294"
      )

    assert Citation.plain(article) ==
             ~s(Barnett, Timothy Brian. "Lope and Tasso". Bulletin of the Comediantes. 2005, 57, 2, p. 238-294.)
  end

  test "a play in an anthology: its translator, then the book's editor, title and imprint" do
    section =
      entry(
        kind: "translation",
        pub_type: "book_section",
        analytic_author: "Dryden, John",
        analytic_title: "Tutto per l'amore",
        analytic_translators: "Gerevini, Silvano",
        monogr_editors: "Obertello, Alfredo",
        monogr_title: "Teatro inglese",
        pub_place: "Milano",
        publisher: "Nuova Accademia",
        year_text: "1961",
        pages: "457-521"
      )

    assert Citation.plain(section) ==
             ~s(Dryden, John. "Tutto per l'amore". Tra. Gerevini, Silvano. Ed. Obertello, Alfredo. Teatro inglese. Milano: Nuova Accademia, 1961, p. 457-521.)
  end

  test "a translated book: series and original title close it, and no full stop is doubled" do
    book =
      entry(
        kind: "translation",
        pub_type: "book",
        monogr_author: "Peele, George",
        monogr_title: "Altweibermär",
        monogr_translators: "Harbecke, Ulrich J.",
        pub_place: "Weinheim",
        publisher: "Deutscher Laienspiel-Verlag",
        year_text: "1967",
        series: "Das Bühnenspiel",
        original_title: "Old Wife's Tale"
      )

    assert Citation.plain(book) ==
             "Peele, George. Altweibermär. Tra. Harbecke, Ulrich J. Weinheim: Deutscher Laienspiel-Verlag, 1967. Das Bühnenspiel. (Orig: Old Wife's Tale)"
  end

  test "a scholar's edition marks its editor, and a missing level leaves no stray full stop" do
    edition =
      entry(
        kind: "criticism",
        pub_type: "scholarly_edition",
        analytic_author: "Agheana, Ion T.",
        analytic_title: "La dialéctica",
        monogr_title: "Hispanic Studies in Honor of Frank P. Casa",
        pub_place: "New York",
        publisher: "Peter Lang",
        year_text: "1997",
        pages: "281-288"
      )

    assert Citation.plain(edition) ==
             ~s(Agheana, Ion T., ed. "La dialéctica". Hispanic Studies in Honor of Frank P. Casa. New York: Peter Lang, 1997, p. 281-288.)
  end

  test "a play in collected works: editor first, italic titles, In:, and the link's volume and pages" do
    rowe =
      entry(
        kind: "modern_edition",
        pub_type: "book_section",
        analytic_editors: "Rowe, Nicholas",
        analytic_title: "Hamlet",
        analytic_author: "Shakespeare, William",
        monogr_title: "The Works of Mr. William Shakespeare",
        pub_place: "London",
        publisher: "Jacob Tonson",
        year_text: "1709",
        volumes_total: "6",
        volume: "1",
        pages: "1-50"
      )

    link = %Link{volume: "5", pages: "2366-2466"}

    assert Citation.plain(rowe, link) ==
             "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 5. London: Jacob Tonson, 1709, pp. 2366-2466, 6 vols."

    assert italics(Citation.parts(rowe, link)) == ["Hamlet", "The Works of Mr. William Shakespeare"]
    assert Citation.plain(rowe) =~ "Vol. 1. London: Jacob Tonson, 1709, pp. 1-50, 6 vols."
  end

  test "a modern edition as a book: series and the printed note close it; internal fields never print" do
    arden =
      entry(
        kind: "modern_edition",
        pub_type: "book",
        monogr_editors: "Thompson, Ann; Taylor, Neil",
        monogr_title: "Hamlet",
        monogr_author: "Shakespeare, William",
        pub_place: "London",
        publisher: "Thomson Learning",
        year_text: "2006",
        edition: "2nd",
        series: "The Arden Shakespeare",
        public_note: "Third series",
        note: "Revisar el cuarto",
        siglum: "ARD3Q2"
      )

    assert Citation.plain(arden, %Link{note: "Préstamo"}) ==
             "Thompson, Ann; Taylor, Neil, ed. Hamlet. Shakespeare, William. 2nd ed. London: Thomson Learning, 2006. The Arden Shakespeare. Third series."
  end

  test "an edition typed with its abbreviation is not abbreviated twice" do
    assert Citation.plain(
             entry(kind: "criticism", pub_type: "book", monogr_title: "T", edition: "2nd ed")
           ) == "T. 2nd ed."
  end

  test "<<…>> inside a title is italics" do
    grilli =
      entry(
        kind: "criticism",
        pub_type: "article",
        analytic_author: "Grilli, Giuseppe",
        analytic_title: "Lope y su fábula de <<Adonis y Venus>>",
        monogr_title: "Anuario Lope de Vega",
        year_text: "1998"
      )

    assert italics(Citation.parts(grilli)) == ["Adonis y Venus"]

    assert Citation.plain(grilli) ==
             ~s(Grilli, Giuseppe. "Lope y su fábula de Adonis y Venus". Anuario Lope de Vega. 1998.)
  end

  test "the web address comes last, with its access date" do
    kyd =
      entry(
        kind: "translation",
        pub_type: "book_section",
        analytic_author: "Kyd, Thomas",
        analytic_title: "La tragedia española",
        monogr_title: "EMOTHE",
        year_text: "2018",
        url: "https://emothe.uv.es/x.php",
        url_accessed_on: "2019-05-12"
      )

    assert Citation.plain(kyd) ==
             ~s(Kyd, Thomas. "La tragedia española". EMOTHE. 2018. URL: https://emothe.uv.es/x.php (acc. 2019-05-12))

    assert %{url: "https://emothe.uv.es/x.php", href: "https://emothe.uv.es/x.php"} in Citation.parts(
             kyd
           )
  end

  # Review focus 1 and 5: what a curator or the FileMaker dump can put in a field.
  test "only http and https addresses become links, and every field is escaped" do
    base = entry(kind: "criticism", pub_type: "book", monogr_title: "<script>alert(1)</script>")

    for url <- ["javascript:alert(1)", ". http://emothe.uv.es/x.php"] do
      assert %{url: ^url, href: nil} = List.last(Citation.parts(%{base | url: url}))
      refute Phoenix.HTML.safe_to_string(Citation.html(%{base | url: url})) =~ "<a "
    end

    html =
      %{base | url: "https://e.org/?a=1&b=<2>"}
      |> Citation.html()
      |> Phoenix.HTML.safe_to_string()

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ ~s(<a href="https://e.org/?a=1&amp;b=&lt;2&gt;" rel="noopener">)
  end

  test "html marks italics with em" do
    html =
      entry(kind: "modern_edition", pub_type: "book", monogr_title: "Hamlet")
      |> Citation.html()
      |> Phoenix.HTML.safe_to_string()

    assert html == "<em>Hamlet</em>."
  end
end
```

- [ ] **Step 2: Run them and see them fail**

Run: `mix test test/playcode/bibliography/citation_test.exs`
Expected: `module Playcode.Bibliography.Citation is not available`.

- [ ] **Step 3: Write the renderer**

`lib/playcode/bibliography/citation.ex`:

```elixir
defmodule Playcode.Bibliography.Citation do
  @moduledoc """
  A bibliography entry as printed: FileMaker's elements and labels in one consistent order
  per kind, without its `{Falta …}` placeholders or doubled full stops. The order is in
  "Display" in docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  The admin page, `/plays/:code`, the static site and the sort order all go through
  `parts/2`, so they cannot drift apart. The labels are FileMaker's and are not
  translated.
  """

  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.PlayContent.InlineMarkup

  @doc """
  The citation as `%{text: binary, italic: boolean}` segments, as `InlineMarkup.parts/1`
  returns them, ending with `%{url: url, href: href}` when there is an address. `href` is
  the address only when it is http or https, so nothing else can become a link.
  """
  def parts(%Entry{} = entry, link \\ nil) do
    entry
    |> pieces(link)
    |> List.flatten()
    |> Enum.join(" ")
    |> InlineMarkup.parts()
    |> Kernel.++(url_parts(entry))
  end

  @doc "The citation as plain text."
  def plain(%Entry{} = entry, link \\ nil) do
    entry
    |> parts(link)
    |> Enum.map_join(fn
      %{url: url} -> url
      %{text: text} -> text
    end)
  end

  @doc "The citation as safe HTML: `<em>` for italics, `<a>` for an http(s) address, the rest escaped."
  def html(%Entry{} = entry, link \\ nil) do
    {:safe, entry |> parts(link) |> Enum.map(&segment_html/1)}
  end

  defp segment_html(%{href: href, url: url}) when is_binary(href),
    do: [~s(<a href="), escape(href), ~s(" rel="noopener">), escape(url), "</a>"]

  defp segment_html(%{url: url}), do: escape(url)
  defp segment_html(%{text: text, italic: true}), do: ["<em>", escape(text), "</em>"]
  defp segment_html(%{text: text}), do: escape(text)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # --- Modern editions: Editors, ed. <<Title>>. Author. In: … ---

  defp pieces(%Entry{kind: "modern_edition"} = e, link) do
    analytic =
      edition_level(e.analytic_editors, e.analytic_title, e.analytic_author, e.analytic_translators)

    monogr =
      edition_level(e.monogr_editors, e.monogr_title, e.monogr_author, e.monogr_translators)

    [
      analytic,
      if(analytic != [] and monogr != [], do: "In:", else: []),
      monogr,
      edition(e.edition),
      with_value(volume_of(e, link), &"Vol. #{sentence(&1)}"),
      imprint(e, pages_of(e, link), "pp."),
      the_rest(e)
    ]
  end

  # --- Criticism, translations, adaptations: Author. "Title". Container. … ---

  defp pieces(%Entry{pub_type: "article"} = e, link) do
    [
      lead(e),
      edition(e.edition),
      [e.year_text, volume_of(e, link), e.issue, page_label(pages_of(e, link), "p.")]
      |> Enum.filter(&present?/1)
      |> join_sentence(),
      the_rest(e)
    ]
  end

  defp pieces(%Entry{} = e, link) do
    [
      lead(e),
      edition(e.edition),
      with_value(volume_of(e, link), &"Vol. #{sentence(&1)}"),
      imprint(e, pages_of(e, link), "p."),
      the_rest(e)
    ]
  end

  defp edition_level(editors, title, author, translators) do
    List.flatten([
      with_value(editors, &"#{&1}, ed."),
      with_value(title, &italic_sentence/1),
      with_value(author, &sentence/1),
      with_value(translators, &"Tra. #{sentence(&1)}")
    ])
  end

  # With an analytic level, the article or chapter leads and the book or journal follows.
  # A journal has no author line: FileMaker never printed one.
  defp lead(%Entry{} = e) do
    if present?(e.analytic_author) or present?(e.analytic_title) do
      [
        with_value(e.analytic_author, fn author ->
          if e.pub_type == "scholarly_edition", do: "#{author}, ed.", else: sentence(author)
        end),
        with_value(e.analytic_title, &~s("#{&1}".)),
        with_value(e.analytic_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.analytic_translators, &"Tra. #{sentence(&1)}"),
        if(e.pub_type == "article", do: [], else: with_value(e.monogr_author, &sentence/1)),
        with_value(e.monogr_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.monogr_title, &sentence/1),
        with_value(e.monogr_translators, &"Tra. #{sentence(&1)}")
      ]
    else
      [
        with_value(e.monogr_author, &sentence/1),
        with_value(e.monogr_title, &sentence/1),
        with_value(e.monogr_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.analytic_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.monogr_translators, &"Tra. #{sentence(&1)}"),
        with_value(e.analytic_translators, &"Tra. #{sentence(&1)}")
      ]
    end
  end

  # Place: Publisher, Year, p. pages, N vols.
  defp imprint(e, pages, page_label) do
    place = [e.pub_place, e.publisher] |> Enum.filter(&present?/1) |> Enum.join(": ")

    [place, e.year_text, page_label(pages, page_label), with_value(e.volumes_total, &"#{&1} vols.")]
    |> List.flatten()
    |> Enum.filter(&present?/1)
    |> join_sentence()
  end

  defp the_rest(e) do
    [
      with_value(e.series, &sentence/1),
      with_value(e.original_title, &"(Orig: #{&1})"),
      with_value(e.public_note, &sentence/1)
    ]
  end

  # "2nd" becomes "2nd ed."; "2nd ed" and "2nd ed." are left as typed.
  defp edition(value) do
    with_value(value, fn text ->
      if text =~ ~r/\bed\.?$/i, do: sentence(text), else: "#{text} ed."
    end)
  end

  defp page_label(pages, label), do: with_value(pages, &"#{label} #{&1}")

  # A link's volume and pages say where this play sits in the edition, so they win.
  defp volume_of(e, link), do: link_value(link, :volume) || e.volume
  defp pages_of(e, link), do: link_value(link, :pages) || e.pages

  defp link_value(%Link{} = link, key) do
    value = Map.get(link, key)
    if present?(value), do: value
  end

  defp link_value(_link, _key), do: nil

  defp url_parts(%Entry{url: url} = e) do
    if present?(url) do
      url = String.trim(url)
      href = if url =~ ~r{\Ahttps?://}i, do: url

      [%{text: " URL: ", italic: false}, %{url: url, href: href}] ++
        with_value(e.url_accessed_on, &%{text: " (acc. #{&1})", italic: false})
    else
      []
    end
  end

  defp join_sentence([]), do: []
  defp join_sentence(bits), do: bits |> Enum.map(&String.trim/1) |> Enum.join(", ") |> sentence()

  defp with_value(value, fun), do: if(present?(value), do: [fun.(String.trim(value))], else: [])

  defp sentence(text), do: if(stops?(text), do: text, else: text <> ".")

  # ponytail: a title that itself contains <<…>> nests the markers and the inner pair wins;
  # FileMaker titles rarely do. Split the title on its markers if a curator hits it.
  defp italic_sentence(title), do: if(stops?(title), do: "<<#{title}>>", else: "<<#{title}>>.")

  defp stops?(text), do: String.ends_with?(text, [".", "?", "!"])

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
```

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode/bibliography/citation_test.exs`
Expected: all pass. If a punctuation assertion fails, read the diff before touching code. The expected strings were derived from the rules above, and a failure there usually means a `sentence/1` call is missing or doubled.

- [ ] **Step 5: Refactor while green**

`pieces/2` has three clauses that share the tail. If extracting the tail reads better, do it; otherwise leave it. Run `mix format && mix compile --warnings-as-errors && mix test`.

- [ ] **Step 6: Commit**

```bash
git add lib/playcode/bibliography/citation.ex test/playcode/bibliography/citation_test.exs
git commit -m "feat(bibliography): print an entry the way FileMaker did

One renderer for every surface: segments, plain text and escaped HTML.
FileMaker's labels and element order, without its {Falta} placeholders or
doubled full stops; only http(s) addresses become links.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode/bibliography/citation.ex test/playcode/bibliography/citation_test.exs
```

---

### Task 3: Grouping and order

**Files:**
- Modify: `lib/playcode/bibliography.ex`
- Test: `test/playcode/bibliography_test.exs`

**Interfaces:**
- Consumes: `Citation.plain/2` (Task 2), `list_links/1` and `Entry.kinds/0` (Task 1).
- Produces:
  - **`Bibliography.list_for_play(play_id)`** returns `[{kind, [{language | nil, [%Link{entry: %Entry{}}]}]}]`:
    - kinds in `Entry.kinds/0` order, only those that have links
    - translations subgrouped `es en fr it pt de`, then `nil`; every other kind has the single group `nil`
  - **`Bibliography.sort_key(link)`:** the folded plain citation, leading punctuation removed.
  - **`Bibliography.fold(text)`:** NFD, combining marks removed, downcased, trimmed.

- [ ] **Step 1: Write the failing tests**

Append to `test/playcode/bibliography_test.exs`:

```elixir
  describe "list_for_play/1" do
    test "groups by kind in display order, leaving out empty kinds" do
      play = play_fixture()
      bibliography_fixture(play, %{"kind" => "adaptation", "monogr_title" => "Adapted"})
      bibliography_fixture(play, %{"kind" => "criticism", "monogr_title" => "Studied"})
      bibliography_fixture(play, %{"kind" => "modern_edition", "monogr_title" => "Edited"})

      assert Enum.map(Bibliography.list_for_play(play.id), &elem(&1, 0)) ==
               ~w(modern_edition criticism adaptation)
    end

    test "sorts by the first name printed, ignoring case, accents and opening quotes" do
      play = play_fixture()

      for {author, title} <- [
            {"Zúñiga, Ana", "Z"},
            {nil, ~s("Ópera" y teatro)},
            {"álvarez, Luis", "A"},
            {"Barnett, Tim", "B"}
          ] do
        bibliography_fixture(play, %{"monogr_author" => author, "monogr_title" => title})
      end

      assert [{"criticism", [{nil, links}]}] = Bibliography.list_for_play(play.id)

      assert Enum.map(links, & &1.entry.monogr_author) ==
               ["álvarez, Luis", "Barnett, Tim", nil, "Zúñiga, Ana"]
    end

    test "translations are subgrouped by language, unknown last" do
      play = play_fixture()

      for {language, title} <- [
            {nil, "Sin idioma"},
            {"fr", "Traduction"},
            {"es", "Traducción"},
            {"en", "Translation"}
          ] do
        bibliography_fixture(play, %{
          "kind" => "translation",
          "language" => language,
          "monogr_title" => title
        })
      end

      assert [{"translation", groups}] = Bibliography.list_for_play(play.id)
      assert Enum.map(groups, &elem(&1, 0)) == ["es", "en", "fr", nil]
    end
  end
```

- [ ] **Step 2: Run and see them fail**

Run: `mix test test/playcode/bibliography_test.exs`
Expected: `function Playcode.Bibliography.list_for_play/1 is undefined`.

- [ ] **Step 3: Implement**

In `lib/playcode/bibliography.ex`, change the alias line to `alias Playcode.Bibliography.{Citation, Entry, Link}` and add after `list_links/1`:

```elixir
  @language_order ~w(es en fr it pt de)

  @doc """
  The play's bibliography as every surface shows it: `[{kind, [{language, [link]}]}]`.
  Kinds come in `Entry.kinds/0` order, only those with entries. Translations are
  subgrouped by language (`es en fr it pt de`, unknown last); every other kind has one
  group, `nil`. Within a group, links sort by their printed citation (`sort_key/1`).
  """
  def list_for_play(play_id) do
    by_kind =
      play_id
      |> list_links()
      |> Enum.sort_by(&{sort_key(&1), &1.entry_id})
      |> Enum.group_by(& &1.entry.kind)

    for kind <- Entry.kinds(), Map.has_key?(by_kind, kind) do
      {kind, subgroups(kind, by_kind[kind])}
    end
  end

  defp subgroups("translation", links) do
    by_language = Enum.group_by(links, & &1.entry.language)

    for language <- @language_order ++ [nil], Map.has_key?(by_language, language) do
      {language, by_language[language]}
    end
  end

  defp subgroups(_kind, links), do: [{nil, links}]

  @doc """
  How a link sorts: its printed citation, folded, without leading quotes or punctuation.
  A citation starts with the first name printed, so this is "alphabetical by author".
  """
  def sort_key(%Link{entry: %Entry{} = entry} = link) do
    entry
    |> Citation.plain(link)
    |> fold()
    |> String.replace(~r/^[^\p{L}\p{N}]+/u, "")
  end

  @doc "Lower case, accents removed, trimmed: how the bibliography compares text."
  def fold(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.trim()
  end
```

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode/bibliography_test.exs`
Expected: pass.

- [ ] **Step 5: Refactor while green, then the full gate**

Run `mix format && mix compile --warnings-as-errors && mix test`.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(bibliography): group by kind, sort alphabetically

Alphabetical by the first name printed, case and accents folded (the
project's answer, 2026-10-07); translations subgrouped by language as on
the current website.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode/bibliography.ex test/playcode/bibliography_test.exs
```

---

### Task 4: Reading the FileMaker tables and planning the import

**Files:**
- Create: `lib/playcode/import/filemaker_xml.ex`, `lib/playcode/import/bibliography.ex`
- Create: the six files under `test/fixtures/filemaker/ctce_dades/` (below)
- Test: `test/playcode/import/filemaker_xml_test.exs`, `test/playcode/import/bibliography_test.exs`

**Interfaces:**
- Consumes: `Entry.named?/1`, `Entry`, `Link` (Task 1); `FilemakerSync.base_code/1`.
- Produces:
  - **`FilemakerXml.read(path)`** → `{:ok, [%{field => value}]}`, values trimmed, `""` when empty; or `{:error, reason}`.
  - **`Playcode.Import.Bibliography`, setup and mapping:**
    - `default_dir/0` (`"doc/ctce_dades"`)
    - `load(dir)` → `{:ok, %{bib_links, bib_records, edition_links, editions, cities, publishers}}`, or `{:error, {file, reason}}`
    - `lookups(data)` → `%{cities: %{id => name}, publishers: %{id => name}}`
    - `record_attrs(row, lookups)`, `edition_attrs(row, lookups)` → entry attribute maps with atom keys
    - `editions_by_id(rows)` → `%{id => row}`, preferring a copy that names something
  - **`plan(data, plays)`:** reads the database and never writes. Returns `%{entries: %{ref => attrs}, existing: [ref], links: [%{play_id, code, filemaker_id, volume, pages, note}], already_imported: [code], skipped: %{reason => [ref]}, not_held: integer}`.
    - A `ref` is `"T12:<id>"` or `"T04:<id>"`.
    - The skip reasons are `:no_record`, `:missing_record`, `:test_record`, `:no_name`, `:duplicate_link` and `:unlinked`.

- [ ] **Step 1: Write the fixture dump**

Every file starts with the same header line, followed by its `METADATA` and `RESULTSET`. An empty column is `<COL><DATA></DATA></COL>`, as in the real export.

`test/fixtures/filemaker/ctce_dades/T13.1_Ciudad.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?><FMPXMLRESULT xmlns="http://www.filemaker.com/fmpxmlresult"><ERRORCODE>0</ERRORCODE><PRODUCT BUILD="02-13-2018" NAME="FileMaker" VERSION="Pro 16.0.5"/><DATABASE DATEFORMAT="D/m/yyyy" LAYOUT="" NAME="ctce_dades.fmp12" RECORDS="4" TIMEFORMAT="k:mm:ss "/><METADATA><FIELD EMPTYOK="YES" MAXREPEAT="1" NAME="_kp_IdCiudad" TYPE="NUMBER"/><FIELD EMPTYOK="YES" MAXREPEAT="1" NAME="Ciu_Ciudad" TYPE="TEXT"/></METADATA><RESULTSET FOUND="4"><ROW MODID="1" RECORDID="1"><COL><DATA>1</DATA></COL><COL><DATA>Madrid</DATA></COL></ROW><ROW MODID="1" RECORDID="2"><COL><DATA>2</DATA></COL><COL><DATA>London</DATA></COL></ROW><ROW MODID="1" RECORDID="3"><COL><DATA>3</DATA></COL><COL><DATA>Weinheim</DATA></COL></ROW><ROW MODID="1" RECORDID="4"><COL><DATA>4</DATA></COL><COL><DATA></DATA></COL></ROW></RESULTSET></FMPXMLRESULT>
```

`test/fixtures/filemaker/ctce_dades/T13.2_Editorial.xml`:

```xml
<?xml version="1.0" encoding="UTF-8" ?><FMPXMLRESULT xmlns="http://www.filemaker.com/fmpxmlresult"><ERRORCODE>0</ERRORCODE><PRODUCT BUILD="02-13-2018" NAME="FileMaker" VERSION="Pro 16.0.5"/><DATABASE DATEFORMAT="D/m/yyyy" LAYOUT="" NAME="ctce_dades.fmp12" RECORDS="4" TIMEFORMAT="k:mm:ss "/><METADATA><FIELD EMPTYOK="YES" MAXREPEAT="1" NAME="_kp_IdEditorial" TYPE="NUMBER"/><FIELD EMPTYOK="YES" MAXREPEAT="1" NAME="Edi_Editorial" TYPE="TEXT"/></METADATA><RESULTSET FOUND="4"><ROW MODID="1" RECORDID="1"><COL><DATA>1</DATA></COL><COL><DATA>Iberoamericana</DATA></COL></ROW><ROW MODID="1" RECORDID="2"><COL><DATA>2</DATA></COL><COL><DATA>Thomson Learning</DATA></COL></ROW><ROW MODID="1" RECORDID="3"><COL><DATA>3</DATA></COL><COL><DATA>Jacob Tonson</DATA></COL></ROW><ROW MODID="1" RECORDID="4"><COL><DATA>4</DATA></COL><COL><DATA>Deutscher Laienspiel-Verlag</DATA></COL></ROW></RESULTSET></FMPXMLRESULT>
```

`test/fixtures/filemaker/ctce_dades/T12.1_BibliografiaSelecta.xml` has 18 fields, in this `METADATA` order:

`_kp_IdBiblioSelecta, _k_IdBiblioSelCategoria, _k_IdBiblioSelTipo, _k_IdBiblioSelIdioma, BibSel_Autor, BibSel_Titulo, BibSel_Traductor, BibSel_Autor2, BibSel_Titulo2, BibSel_Traductor2, BibSel_TituloOriginal, BibSel_NumVolTomo, BibSel_Ejemplar, BibSel_Pag, BibSel_Ano, BibSel_Nota, _k_IdCiudad, _k_IdEditorial`

and these seven rows (empty cells shown as `·`):

| id | cat | type | lang | Autor | Titulo | Traductor | Autor2 | Titulo2 | Traductor2 | TituloOriginal | NumVolTomo | Ejemplar | Pag | Ano | Nota | Ciudad | Editorial |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 3 | Barnett, Timothy Brian | Lope and Tasso | · | · | Bulletin of the Comediantes | · | · | 57 | 2 | 238-294 | 2005 | Sobre Tasso | · | · |
| 2 | · | 2 | 1 | Grilli, Giuseppe | Lope y su fábula de `&lt;&lt;`Adonis y Venus`&gt;&gt;` | · | De Armas, Frederick A. | Hacia la tragedia áurea | · | · | · | · | 97-115 | 2008 | · | 1 | 1 |
| 3 | 2 | 4 | 6 | · | Das Bühnenspiel | · | Peele, George | Altweibermär | Harbecke, Ulrich J. | Old Wife's Tale | · | · | · | 1967 | · | 3 | 4 |
| 4 | 1 | 1 | 3 | Taylor, Miles | Teach Me This Pedlar's French | · | · | Renaissance and Reformation | · | · | 29 | 4 | 107-24 | 2005 | · | · | · |
| 5 | 1 | 2 | · | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| 6 | 1 | 4 | 3 | · | · | · | Bevington, David | Medieval Drama | · | · | · | · | · | 1975 | · | · | B.R. Grüner Publishing Company |
| 7 | 1 | 4 | 1 | · | · | · | Nadie, Juan | Sin enlace | · | · | · | · | · | 1990 | · | · | · |

Write each row as `<ROW MODID="1" RECORDID="n">` followed by 18 `<COL><DATA>…</DATA></COL>` in field order. Row 2's title is written escaped, exactly `Lope y su fábula de &lt;&lt;Adonis y Venus&gt;&gt;`, as the real export stores it.

`test/fixtures/filemaker/ctce_dades/T12_ObraBibliografiaSelecta.xml` has the fields `_k_IdBiblioSelecta, _k_IdObraTitulo, ObrBibSel_Nota` and these rows, in this order:

| record | version | note |
|---|---|---|
| 1 | 38 | doi:http://dx.doi.org/10.2307/3190039 |
| 2 | 38 | · |
| 3 | 10 | · |
| 4 | 38 | · |
| 4 | 10 | · |
| 5 | 38 | · |
| 6 | 10 | · |
| · | 38 | · |
| 99 | 38 | · |
| 1 | 38 | · |
| 1 | 999 | · |

`test/fixtures/filemaker/ctce_dades/T04.1_EdModerna.xml` has 15 fields:

`_kp_IdEdicionModerna, _k_IdEdicionModernaTipo, _k_IdEdicionModernaIdioma, EdiMod_Autor, EdiMod_Titulo, EdiMod_Editor, EdiMod_Titulo2, EdiMod_Titulo3, EdiMod_VolTomo, EdiMod_Ano, EdiMod_Siglas, EdiMod_Nota, EdiMod_Referencia, _k_IdCiudad, _k_IdEditorial`

| id | tipo | idioma | Autor | Titulo | Editor | Titulo2 | Titulo3 | VolTomo | Ano | Siglas | Nota | Referencia | Ciudad | Editorial |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 40 | 1 | 3 | Shakespeare, William | Hamlet | Thompson, Ann; Taylor, Neil | The Arden Shakespeare | · | · | 2006 | ARD3Q2 | Third series | · | 2 | 2 |
| 52 | 2 | 3 | Shakespeare, William | Hamlet | Rowe, Nicholas | The Works of Mr. William Shakespeare | · | 6 | 1709 | ROWE1 | · | · | 2 | 3 |
| 9 | · | 1 | test | · | · | · | · | · | · | edm1 | y esto una nota | esto es una prueba | · | · |
| 44 | · | · | · | · | · | · | · | · | · | OXF2 | · | Wells, Stanley, and Gary Taylor, gen. eds. | · | · |
| 576 | · | · | · | · | · | · | · | · | · | · | · | · | · | · |
| 576 | 1 | 3 | Shakespeare, William | Antony and Cleopatra | Wilders, John | · | · | · | 1995 | · | · | · | 2 | 2 |

`test/fixtures/filemaker/ctce_dades/T04_ObraModernaRecomendada.xml` has the fields `_kp_IdObraEdModRecomendada, _k_IdEdicionModerna, _k_IdObraTitulo, ObraEdMod_Volumen, ObraEdMod_Paginas`:

| link | edition | version | volume | pages |
|---|---|---|---|---|
| 1 | 40 | 10 | · | · |
| 2 | 52 | 10 | 5 | 2366-2466 |
| 3 | 52 | 38 | 7 | 100-200 |
| 4 | 9 | 10 | · | · |
| 5 | 44 | 38 | · | · |
| 6 | 576 | 38 | · | · |
| 7 | · | 10 | · | · |
| 8 | 777 | 10 | · | · |

- [ ] **Step 2: Write the failing tests**

`test/playcode/import/filemaker_xml_test.exs`:

```elixir
defmodule Playcode.Import.FilemakerXmlTest do
  @moduledoc "The FMPXMLRESULT export FileMaker writes for one table."
  use ExUnit.Case, async: true

  alias Playcode.Import.FilemakerXml

  @dump "test/fixtures/filemaker/ctce_dades"

  test "one map per row, keyed by the METADATA field names, an empty column as \"\"" do
    assert {:ok, rows} = FilemakerXml.read(Path.join(@dump, "T13.1_Ciudad.xml"))

    assert rows == [
             %{"_kp_IdCiudad" => "1", "Ciu_Ciudad" => "Madrid"},
             %{"_kp_IdCiudad" => "2", "Ciu_Ciudad" => "London"},
             %{"_kp_IdCiudad" => "3", "Ciu_Ciudad" => "Weinheim"},
             %{"_kp_IdCiudad" => "4", "Ciu_Ciudad" => ""}
           ]
  end

  test "entities are decoded, so FileMaker's <<…>> italics survive" do
    {:ok, rows} = FilemakerXml.read(Path.join(@dump, "T12.1_BibliografiaSelecta.xml"))
    grilli = Enum.find(rows, &(&1["_kp_IdBiblioSelecta"] == "2"))
    assert grilli["BibSel_Titulo"] == "Lope y su fábula de <<Adonis y Venus>>"
  end

  @tag :tmp_dir
  test "anything else is refused", %{tmp_dir: dir} do
    other = Path.join(dir, "other.xml")
    File.write!(other, "<root/>")

    assert {:error, :not_fmpxmlresult} = FilemakerXml.read(other)
    assert {:error, _reason} = FilemakerXml.read("test/fixtures/filemaker/export_sample.ndjson")
    assert {:error, :enoent} = FilemakerXml.read(Path.join(dir, "missing.xml"))
  end
end
```

`test/playcode/import/bibliography_test.exs`:

```elixir
defmodule Playcode.Import.BibliographyTest do
  @moduledoc """
  What the bibliography import would write, from a six-table dump cut down to one case per
  rule. The writing itself is tested through the mix task, in test/mix/tasks_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Import.Bibliography

  @dump "test/fixtures/filemaker/ctce_dades"

  setup do
    hamlet = play_fixture(%{"code" => "EMOTHE0010_Hamlet"})
    antony = play_fixture(%{"code" => "EMOTHE0038_AntonyAndCleopatra"})
    {:ok, data} = Bibliography.load(@dump)

    %{plan: Bibliography.plan(data, [hamlet, antony]), hamlet: hamlet, antony: antony}
  end

  test "every skip is listed under its reason", %{plan: plan} do
    assert plan.skipped == %{
             no_record: ["T12 link to version 38", "T04 link to version 10"],
             missing_record: ["T12:99", "T04:777"],
             no_name: ["T12:5", "T04:44"],
             test_record: ["T04:9"],
             duplicate_link: ["T12:1 on EMOTHE0038_AntonyAndCleopatra"],
             unlinked: ["T12:7"]
           }

    assert plan.not_held == 1
  end

  test "a record shared by two plays is one entry with two links", %{plan: plan} do
    assert plan.entries |> Map.keys() |> Enum.sort() ==
             ~w(T04:40 T04:52 T04:576 T12:1 T12:2 T12:3 T12:4 T12:6)

    assert length(plan.links) == 10
    assert Enum.count(plan.links, &(&1.filemaker_id == "T12:4")) == 2
    assert plan.existing == []
  end

  test "an uncategorised record is criticism, and city and publisher come from T13", %{
    plan: plan
  } do
    assert %{kind: "criticism", pub_place: "Madrid", publisher: "Iberoamericana"} =
             plan.entries["T12:2"]

    assert plan.entries["T12:2"].analytic_title == "Lope y su fábula de <<Adonis y Venus>>"
  end

  test "a book's first title is its series", %{plan: plan} do
    assert %{
             kind: "translation",
             pub_type: "book",
             language: "de",
             analytic_title: nil,
             series: "Das Bühnenspiel",
             monogr_title: "Altweibermär",
             original_title: "Old Wife's Tale"
           } = plan.entries["T12:3"]
  end

  test "a publisher key that is not a number is the publisher's name", %{plan: plan} do
    assert plan.entries["T12:6"].publisher == "B.R. Grüner Publishing Company"
  end

  test "the record's note stays internal; the link's note is the link's", %{
    plan: plan,
    antony: antony
  } do
    assert plan.entries["T12:1"].note == "Sobre Tasso"
    link = Enum.find(plan.links, &(&1.play_id == antony.id and &1.filemaker_id == "T12:1"))
    assert link.note =~ "10.2307/3190039"
  end

  test "a chapter edition has two levels, and VolTomo is its number of volumes", %{plan: plan} do
    assert %{
             pub_type: "book_section",
             analytic_editors: "Rowe, Nicholas",
             analytic_title: "Hamlet",
             monogr_title: "The Works of Mr. William Shakespeare",
             volumes_total: "6",
             volume: nil
           } = plan.entries["T04:52"]
  end

  test "a book edition's second title is its series, and its note is printed", %{plan: plan} do
    assert %{
             pub_type: "book",
             monogr_editors: "Thompson, Ann; Taylor, Neil",
             monogr_title: "Hamlet",
             series: "The Arden Shakespeare",
             public_note: "Third series",
             siglum: "ARD3Q2",
             note: nil
           } = plan.entries["T04:40"]
  end

  test "a duplicated edition id uses the copy that names something", %{plan: plan} do
    assert plan.entries["T04:576"].monogr_title == "Antony and Cleopatra"
  end

  test "each play's link carries its own volume and pages", %{
    plan: plan,
    hamlet: hamlet,
    antony: antony
  } do
    link = fn play -> Enum.find(plan.links, &(&1.play_id == play.id and &1.filemaker_id == "T04:52")) end

    assert %{volume: "5", pages: "2366-2466"} = link.(hamlet)
    assert %{volume: "7", pages: "100-200"} = link.(antony)
  end
end
```

- [ ] **Step 3: Run them and see them fail**

Run: `mix test test/playcode/import/filemaker_xml_test.exs test/playcode/import/bibliography_test.exs`
Expected: `module Playcode.Import.FilemakerXml is not available`.

- [ ] **Step 4: Write the reader**

`lib/playcode/import/filemaker_xml.ex`:

```elixir
defmodule Playcode.Import.FilemakerXml do
  @moduledoc """
  Reads one table exported from FileMaker as FMPXMLRESULT: `METADATA/FIELD` names the
  columns, then each `RESULTSET/ROW/COL/DATA` holds one value, in that order. An empty
  column is `<DATA></DATA>`. FileMaker escapes `<<` as `&lt;&lt;`; Saxy decodes it.
  """

  @doc "`{:ok, [%{field_name => value}]}`, values trimmed and `\"\"` when empty."
  def read(path) do
    with {:ok, xml} <- File.read(path),
         {:ok, {"FMPXMLRESULT", _attrs, children}} <- parse(xml) do
      names = children |> child("METADATA") |> elements("FIELD") |> Enum.map(&attribute(&1, "NAME"))

      rows =
        children
        |> child("RESULTSET")
        |> elements("ROW")
        |> Enum.map(fn row ->
          names |> Enum.zip(row |> elements("COL") |> Enum.map(&value/1)) |> Map.new()
        end)

      {:ok, rows}
    else
      {:ok, _other_root} -> {:error, :not_fmpxmlresult}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse(xml) do
    Saxy.SimpleForm.parse_string(xml)
  catch
    # Saxy reports a malformed document as an error tuple; this is only for input that is
    # not text at all.
    _kind, reason -> {:error, reason}
  end

  defp child(children, name), do: Enum.find(children, &match?({^name, _attrs, _children}, &1))

  defp elements(nil, _name), do: []

  defp elements({_name, _attrs, children}, name),
    do: Enum.filter(children, &match?({^name, _attrs, _children}, &1))

  defp attribute({_name, attrs, _children}, key) do
    {^key, value} = List.keyfind(attrs, key, 0)
    value
  end

  defp value(col) do
    col
    |> elements("DATA")
    |> Enum.map_join(" ", fn {_name, _attrs, children} ->
      children |> Enum.filter(&is_binary/1) |> Enum.join()
    end)
    |> String.trim()
  end
end
```

- [ ] **Step 5: Write the import's load, mapping and plan**

`lib/playcode/import/bibliography.ex`:

```elixir
defmodule Playcode.Import.Bibliography do
  @moduledoc """
  The one-time move of the FileMaker bibliography into Playcode (S4). Spec: "Import" in
  docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  `load/1` reads six tables. `plan/2` decides what to write: it reads the database but
  never writes. `apply_plan/2` writes the plan in one transaction.

  A play that already has a `filemaker` link is skipped whole, so a re-run picks up the
  plays added since without undoing a curator's edits or removals. An entry whose
  `filemaker_id` already exists is reused, which keeps a shared edition one entry.
  """

  import Ecto.Query

  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.Import.{FilemakerSync, FilemakerXml}
  alias Playcode.Repo

  @default_dir "doc/ctce_dades"

  @files [
    bib_links: "T12_ObraBibliografiaSelecta.xml",
    bib_records: "T12.1_BibliografiaSelecta.xml",
    edition_links: "T04_ObraModernaRecomendada.xml",
    editions: "T04.1_EdModerna.xml",
    cities: "T13.1_Ciudad.xml",
    publishers: "T13.2_Editorial.xml"
  ]

  # T12.12. A blank category is criticism that was never categorised (the project,
  # 2026-10-07).
  @categories %{"2" => "translation", "3" => "adaptation"}

  # T12.13 and T04.12 share their ids.
  @languages %{"1" => "es", "2" => "fr", "3" => "en", "4" => "it", "5" => "pt", "6" => "de"}

  # T12.11.
  @types %{
    "1" => "article",
    "2" => "book_section",
    "3" => "scholarly_edition",
    "4" => "book",
    "5" => "proceedings",
    "6" => "prologue",
    "7" => "festschrift",
    "8" => "electronic",
    "9" => "thesis",
    "10" => "collection"
  }

  # T04.11: 2 is a chapter; 1 and blank print as a book.
  @chapter "2"

  # T04.1 rows that are FileMaker's own tests, not editions.
  @test_editions ~w(9 147)

  @no_lookups %{cities: %{}, publishers: %{}}

  def default_dir, do: @default_dir

  @doc "Reads the six tables from `dir`."
  def load(dir) do
    Enum.reduce_while(@files, {:ok, %{}}, fn {key, file}, {:ok, data} ->
      case FilemakerXml.read(Path.join(dir, file)) do
        {:ok, rows} -> {:cont, {:ok, Map.put(data, key, rows)}}
        {:error, reason} -> {:halt, {:error, {file, reason}}}
      end
    end)
  end

  @doc "City and publisher names by id, from `T13.1` and `T13.2`."
  def lookups(data) do
    %{
      cities: lookup(data.cities, "_kp_IdCiudad", "Ciu_Ciudad"),
      publishers: lookup(data.publishers, "_kp_IdEditorial", "Edi_Editorial")
    }
  end

  @doc "What `apply_plan/2` would write. Reads the database, writes nothing. See the moduledoc."
  def plan(data, plays) do
    lookups = lookups(data)

    context = %{
      by_code: Enum.group_by(plays, &FilemakerSync.base_code(&1.code)),
      imported: imported_play_ids()
    }

    records = Map.new(data.bib_records, &{&1["_kp_IdBiblioSelecta"], &1})
    editions = editions_by_id(data.editions)

    bib = %{
      table: "T12",
      key: "_k_IdBiblioSelecta",
      rows: records,
      tests: [],
      attrs: &record_attrs(&1, lookups),
      link: &bib_link_attrs/1
    }

    eds = %{
      table: "T04",
      key: "_k_IdEdicionModerna",
      rows: editions,
      tests: @test_editions,
      attrs: &edition_attrs(&1, lookups),
      link: &edition_link_attrs/1
    }

    acc =
      %{
        entries: %{},
        links: [],
        seen: MapSet.new(),
        already_imported: MapSet.new(),
        skipped: %{},
        not_held: 0
      }
      |> walk(data.bib_links, bib, context)
      |> walk(data.edition_links, eds, context)
      |> skip_unlinked(bib, data.bib_links)
      |> skip_unlinked(eds, data.edition_links)

    %{
      entries: acc.entries,
      existing: existing_refs(Map.keys(acc.entries)),
      links: Enum.reverse(acc.links),
      already_imported: acc.already_imported |> MapSet.to_list() |> Enum.sort(),
      skipped: Map.new(acc.skipped, fn {reason, refs} -> {reason, Enum.reverse(refs)} end),
      not_held: acc.not_held
    }
  end

  @doc "A `T12.1` record as entry attributes."
  def record_attrs(row, lookups) do
    type = @types[value(row, "_k_IdBiblioSelTipo")]
    title = value(row, "BibSel_Titulo")

    # A book has no analytic level: FileMaker prints this field after the year, as a
    # series (49 of 51 books that have it).
    {analytic_title, series} = if type == "book", do: {nil, title}, else: {title, nil}

    %{
      kind: Map.get(@categories, value(row, "_k_IdBiblioSelCategoria"), "criticism"),
      pub_type: type,
      language: @languages[value(row, "_k_IdBiblioSelIdioma")],
      analytic_author: value(row, "BibSel_Autor"),
      analytic_title: analytic_title,
      analytic_editors: value(row, "BibSel_Editor"),
      analytic_translators: value(row, "BibSel_Traductor"),
      monogr_author: value(row, "BibSel_Autor2"),
      monogr_title: value(row, "BibSel_Titulo2"),
      monogr_editors: value(row, "BibSel_Editor2"),
      monogr_translators: value(row, "BibSel_Traductor2"),
      original_title: value(row, "BibSel_TituloOriginal"),
      edition: value(row, "BibSel_Edicion"),
      volume: value(row, "BibSel_NumVolTomo"),
      volumes_total: value(row, "BibSel_VolTomoTotal"),
      issue: value(row, "BibSel_Ejemplar"),
      pages: value(row, "BibSel_Pag"),
      year_text: value(row, "BibSel_Ano"),
      url: value(row, "BibSel_URL"),
      url_accessed_on: value(row, "BibSel_URL_FechaAcceso"),
      series: series,
      note: value(row, "BibSel_Nota")
    }
    |> Map.merge(place_and_publisher(row, lookups))
  end

  @doc """
  A `T04.1` edition as entry attributes. A chapter has two levels; a book only the
  monograph, and its second title is printed as a series. `EdiMod_VolTomo` is the
  edition's number of volumes; the play's own volume is on the link.
  """
  def edition_attrs(row, lookups) do
    chapter? = value(row, "_k_IdEdicionModernaTipo") == @chapter
    first = level(row, "")
    second = level(row, "2")

    levels =
      if chapter? do
        first
        |> prefixed("analytic")
        |> Map.merge(prefixed(second, "monogr"))
        |> Map.put(:series, value(row, "EdiMod_Titulo3"))
      else
        # A book's second-level people are never printed by FileMaker; only its second
        # title is, as the series.
        first
        |> prefixed("monogr")
        |> Map.put(:series, second.title || value(row, "EdiMod_Titulo3"))
      end

    %{
      kind: "modern_edition",
      pub_type: if(chapter?, do: "book_section", else: "book"),
      language: @languages[value(row, "_k_IdEdicionModernaIdioma")],
      edition: value(row, "EdiMod_Edicion"),
      pages: value(row, "EdiMod_Pag"),
      volumes_total: value(row, "EdiMod_VolTomo"),
      year_text: value(row, "EdiMod_Ano"),
      url: value(row, "EdiMod_URL"),
      url_accessed_on: value(row, "EdiMod_URL_FechaAcceso"),
      siglum: value(row, "EdiMod_Siglas"),
      public_note: value(row, "EdiMod_Nota")
    }
    |> Map.merge(levels)
    |> Map.merge(place_and_publisher(row, lookups))
  end

  @doc "`T04.1` by id. Id 576 appears twice, one copy blank: the copy that names something wins."
  def editions_by_id(rows) do
    rows
    |> Enum.group_by(& &1["_kp_IdEdicionModerna"])
    |> Map.new(fn {id, [first | _] = copies} ->
      {id, Enum.find(copies, first, &Entry.named?(edition_attrs(&1, @no_lookups)))}
    end)
  end

  defp walk(acc, links, table, context) do
    Enum.reduce(links, acc, fn row, acc ->
      id = row[table.key] || ""
      ref = "#{table.table}:#{id}"

      cond do
        id == "" ->
          skip(acc, :no_record, "#{table.table} link to version #{row["_k_IdObraTitulo"]}")

        not Map.has_key?(table.rows, id) ->
          skip(acc, :missing_record, ref)

        id in table.tests ->
          skip(acc, :test_record, ref)

        true ->
          attrs = table.attrs.(table.rows[id])

          if Entry.named?(attrs),
            do: link_versions(acc, context, ref, attrs, row["_k_IdObraTitulo"], table.link.(row)),
            else: skip(acc, :no_name, ref)
      end
    end)
  end

  defp link_versions(acc, context, ref, attrs, version, link_attrs) do
    case Map.get(context.by_code, version_code(version), []) do
      [] ->
        %{acc | not_held: acc.not_held + 1}

      plays ->
        Enum.reduce(plays, acc, fn play, acc ->
          cond do
            MapSet.member?(context.imported, play.id) ->
              %{acc | already_imported: MapSet.put(acc.already_imported, play.code)}

            MapSet.member?(acc.seen, {play.id, ref}) ->
              skip(acc, :duplicate_link, "#{ref} on #{play.code}")

            true ->
              link = Map.merge(link_attrs, %{play_id: play.id, code: play.code, filemaker_id: ref})

              %{
                acc
                | entries: Map.put(acc.entries, ref, attrs),
                  links: [link | acc.links],
                  seen: MapSet.put(acc.seen, {play.id, ref})
              }
          end
        end)
    end
  end

  defp skip_unlinked(acc, table, links) do
    linked = MapSet.new(links, & &1[table.key])

    table.rows
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(linked, &1))
    |> Enum.sort()
    |> Enum.reduce(acc, &skip(&2, :unlinked, "#{table.table}:#{&1}"))
  end

  defp skip(acc, reason, ref),
    do: %{acc | skipped: Map.update(acc.skipped, reason, [ref], &[ref | &1])}

  # The play code FileMaker's version id stands for: 38 is EMOTHE0038.
  defp version_code(version) do
    case Integer.parse(version || "") do
      {number, ""} -> "EMOTHE" <> String.pad_leading(Integer.to_string(number), 4, "0")
      _other -> nil
    end
  end

  defp level(row, suffix) do
    %{
      author: value(row, "EdiMod_Autor" <> suffix),
      title: value(row, "EdiMod_Titulo" <> suffix),
      editors: value(row, "EdiMod_Editor" <> suffix),
      translators: value(row, "EdiMod_Traductor" <> suffix)
    }
  end

  defp prefixed(level, "analytic") do
    %{
      analytic_author: level.author,
      analytic_title: level.title,
      analytic_editors: level.editors,
      analytic_translators: level.translators
    }
  end

  defp prefixed(level, "monogr") do
    %{
      monogr_author: level.author,
      monogr_title: level.title,
      monogr_editors: level.editors,
      monogr_translators: level.translators
    }
  end

  # One publisher "key" in T12.1 is a name typed into the key field: a key that is not a
  # number is the name itself.
  defp place_and_publisher(row, lookups) do
    publisher = value(row, "_k_IdEditorial")

    %{
      pub_place: lookups.cities[value(row, "_k_IdCiudad")],
      publisher:
        if(publisher && publisher =~ ~r/^\d+$/,
          do: lookups.publishers[publisher],
          else: publisher
        )
    }
  end

  defp bib_link_attrs(row), do: %{note: value(row, "ObrBibSel_Nota"), volume: nil, pages: nil}

  defp edition_link_attrs(row),
    do: %{
      note: nil,
      volume: value(row, "ObraEdMod_Volumen"),
      pages: value(row, "ObraEdMod_Paginas")
    }

  defp lookup(rows, key, name), do: Map.new(rows, &{&1[key], value(&1, name)})

  defp value(row, field) do
    case row[field] do
      nil -> nil
      text -> if String.trim(text) == "", do: nil, else: String.trim(text)
    end
  end

  defp imported_play_ids do
    Link
    |> where([l], l.origin == "filemaker")
    |> distinct(true)
    |> select([l], l.play_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp existing_refs([]), do: []

  defp existing_refs(refs) do
    Entry
    |> where([e], e.filemaker_id in ^refs)
    |> select([e], e.filemaker_id)
    |> Repo.all()
  end
end
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/playcode/import/filemaker_xml_test.exs test/playcode/import/bibliography_test.exs`
Expected: pass. If the skips test fails on order, compare against the file order of the two link tables. `skip/3` prepends and `plan/2` reverses, so each list is in file order, T12 before T04.

- [ ] **Step 7: Refactor while green, then the full gate**

Run `mix format && mix compile --warnings-as-errors && mix test`.

- [ ] **Step 8: Commit**

```bash
git commit -m "feat(import): read FileMaker's bibliography tables and plan the move

FMPXMLRESULT reader on Saxy, and the mapping the spec describes: blank
category is criticism, a book's first title is its series, VolTomo is an
edition's number of volumes, EdiMod_Nota is printed. Broken and unlinked
records are skipped and listed by reason.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode/import/filemaker_xml.ex lib/playcode/import/bibliography.ex test/playcode/import/filemaker_xml_test.exs test/playcode/import/bibliography_test.exs test/fixtures/filemaker/ctce_dades
```

---

### Task 5: Writing the import — mix task and release function

**Files:**
- Modify: `lib/playcode/import/bibliography.ex` (add `apply_plan/2`, `report/1`)
- Create: `lib/mix/tasks/playcode.import.bibliography.ex`
- Modify: `lib/playcode/release.ex`
- Test: `test/mix/tasks_test.exs`

**Interfaces:**
- Consumes: `load/1` and `plan/2` (Task 4); `FilemakerSync.all_plays/0`.
- Produces:
  - **`Bibliography.apply_plan(plan, opts \\ [])`** → `{:ok, %{entries: created, links: n}}`, with `opts[:user_id]`.
  - **`Bibliography.report(plan)`** → `[line]`.
  - **`Playcode.Release.import_bibliography(dir, opts \\ [])`**, with `dry_run: true`.

- [ ] **Step 1: Write the failing tests**

In `test/mix/tasks_test.exs`, add `alias Playcode.Bibliography` beside the other aliases. Add this helper at module level, next to `tmp_dir/0`, because a `describe` block holds tests, not functions:

```elixir
  defp citations(play) do
    play.id
    |> Bibliography.list_links()
    |> Enum.map(&Playcode.Bibliography.Citation.plain(&1.entry, &1))
  end
```

Then add:

```elixir
  describe "playcode.import.bibliography" do
    @dump "test/fixtures/filemaker/ctce_dades"

    setup do
      %{
        hamlet: play_fixture(%{"code" => "EMOTHE0010_Hamlet"}),
        antony: play_fixture(%{"code" => "EMOTHE0038_AntonyAndCleopatra"})
      }
    end

    test "--dry-run prints the plan and writes nothing", %{hamlet: hamlet} do
      out = run("playcode.import.bibliography", ["--path", @dump, "--dry-run"])

      assert out =~ "EMOTHE0010_Hamlet  5 links"
      assert out =~ "bibliography: 5 entries (0 already in Playcode), 6 links on 2 plays"
      assert out =~ "modern editions: 3 entries (0 already in Playcode), 4 links on 2 plays"
      assert out =~ "skipped, test_record: 1  T04:9"
      assert out =~ "links to versions not held: 1"
      assert out =~ "dry run, nothing written"
      assert Bibliography.list_links(hamlet.id) == []
    end

    test "writes each entry once, as FileMaker printed it, with each play's own pages", %{
      hamlet: hamlet,
      antony: antony
    } do
      assert run("playcode.import.bibliography", ["--path", @dump]) =~
               "created 8 entries and 10 links"

      assert "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 5. London: Jacob Tonson, 1709, pp. 2366-2466, 6 vols." in citations(
               hamlet
             )

      assert "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 7. London: Jacob Tonson, 1709, pp. 100-200, 6 vols." in citations(
               antony
             )

      assert "Peele, George. Altweibermär. Tra. Harbecke, Ulrich J. Weinheim: Deutscher Laienspiel-Verlag, 1967. Das Bühnenspiel. (Orig: Old Wife's Tale)" in citations(
               hamlet
             )

      assert "Thompson, Ann; Taylor, Neil, ed. Hamlet. Shakespeare, William. London: Thomson Learning, 2006. The Arden Shakespeare. Third series." in citations(
               hamlet
             )

      [rowe] = for l <- Bibliography.list_links(hamlet.id), l.entry.volumes_total == "6", do: l
      assert Bibliography.link_counts([rowe.entry_id]) == %{rowe.entry_id => 2}
      assert rowe.origin == "filemaker"
    end

    test "a re-run skips a play already imported, so a removal stays removed", %{hamlet: hamlet} do
      run("playcode.import.bibliography", ["--path", @dump])
      [first | _] = Bibliography.list_links(hamlet.id)
      {:ok, _} = Bibliography.unlink(first)

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "already imported: 2 plays"
      assert out =~ "created 0 entries and 0 links"
      assert length(Bibliography.list_links(hamlet.id)) == 4
    end

    test "a play added later shares the entries already imported" do
      run("playcode.import.bibliography", ["--path", @dump])
      later = play_fixture(%{"code" => "EMOTHE0038_AntonioYCleopatra"})

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "modern editions: 2 entries (2 already in Playcode), 2 links on 1 plays"
      assert out =~ "created 0 entries and 5 links"
      assert length(Bibliography.list_links(later.id)) == 5
    end

    test "an archived play is left out", %{antony: antony} do
      {:ok, _} = Catalogue.delete_play(antony)
      run("playcode.import.bibliography", ["--path", @dump])
      assert Bibliography.list_links(antony.id) == []
    end

    test "a missing dump is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.bibliography", ["--path", "test/fixtures/filemaker/nope"])
      end
    end
  end
```

- [ ] **Step 2: Run and see them fail**

Run: `mix test test/mix/tasks_test.exs`
Expected: `The task "playcode.import.bibliography" could not be found`.

- [ ] **Step 3: Add `apply_plan/2` and `report/1`**

In `lib/playcode/import/bibliography.ex`, add `alias Playcode.ActivityLog` and:

```elixir
  @doc """
  Writes the plan in one transaction: the entries not yet in Playcode, then every link,
  then one activity-log entry per play. Returns `{:ok, %{entries: created, links: n}}`.
  """
  def apply_plan(plan, opts \\ []) do
    Repo.transaction(
      fn ->
        existing =
          Entry
          |> where([e], e.filemaker_id in ^Map.keys(plan.entries))
          |> select([e], {e.filemaker_id, e.id})
          |> Repo.all()
          |> Map.new()

        created =
          plan.entries
          |> Map.drop(Map.keys(existing))
          |> Map.new(fn {ref, attrs} -> {ref, insert_entry!(ref, attrs)} end)

        ids = Map.merge(existing, created)

        Enum.each(plan.links, fn link ->
          %Link{
            play_id: link.play_id,
            entry_id: Map.fetch!(ids, link.filemaker_id),
            origin: "filemaker"
          }
          |> Link.changeset(Map.take(link, [:volume, :pages, :note]))
          |> Repo.insert!()
        end)

        plan.links
        |> Enum.group_by(& &1.play_id)
        |> Enum.each(fn {play_id, links} ->
          ActivityLog.log!(%{
            user_id: opts[:user_id],
            play_id: play_id,
            action: "import",
            resource_type: "play_bibliography",
            resource_id: play_id,
            changes: %{"links" => length(links)},
            metadata: %{"source" => "filemaker"}
          })
        end)

        %{entries: map_size(created), links: length(plan.links)}
      end,
      timeout: :infinity
    )
  end

  defp insert_entry!(ref, attrs) do
    %Entry{filemaker_id: ref}
    |> Entry.changeset(attrs)
    |> Repo.insert!()
    |> Map.fetch!(:id)
  end

  @doc "The plan as lines of text, for the mix task and the release."
  def report(plan) do
    per_play =
      plan.links
      |> Enum.group_by(& &1.code)
      |> Enum.sort()
      |> Enum.map(fn {code, links} -> "#{code}  #{length(links)} links" end)

    totals =
      for {table, label} <- [{"T12", "bibliography"}, {"T04", "modern editions"}] do
        refs = plan.entries |> Map.keys() |> Enum.filter(&String.starts_with?(&1, table <> ":"))
        links = Enum.filter(plan.links, &String.starts_with?(&1.filemaker_id, table <> ":"))
        plays = links |> Enum.uniq_by(& &1.play_id) |> length()
        reused = Enum.count(refs, &(&1 in plan.existing))

        "#{label}: #{length(refs)} entries (#{reused} already in Playcode), " <>
          "#{length(links)} links on #{plays} plays"
      end

    skipped =
      for {reason, refs} <- Enum.sort(plan.skipped) do
        "skipped, #{reason}: #{length(refs)}  #{Enum.join(refs, ", ")}"
      end

    per_play ++
      [""] ++
      totals ++
      skipped ++
      [
        "already imported: #{length(plan.already_imported)} plays #{Enum.join(plan.already_imported, ", ")}",
        "links to versions not held: #{plan.not_held}"
      ]
  end
```

- [ ] **Step 4: Write the mix task**

`lib/mix/tasks/playcode.import.bibliography.ex`:

```elixir
defmodule Mix.Tasks.Playcode.Import.Bibliography do
  @shortdoc "Move the FileMaker bibliography into the plays we hold"

  @moduledoc """
  Reads FileMaker's bibliography tables (`T12`, `T12.1`, `T04`, `T04.1`, `T13.1`,
  `T13.2`) and links their records to the plays in the database: S4's one-time import.
  Spec: docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

      mix playcode.import.bibliography --dry-run       # print the plan, write nothing
      mix playcode.import.bibliography                 # write it
      mix playcode.import.bibliography --path other/dir

  Re-running is safe: a play already imported is skipped whole, so a curator's edits and
  removals stay. On Fly, use `Playcode.Release.import_bibliography/2`.
  """

  use Mix.Task

  alias Playcode.Import.{Bibliography, FilemakerSync}

  @switches [dry_run: :boolean, path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dir = opts[:path] || Bibliography.default_dir()

    case Bibliography.load(dir) do
      {:ok, data} ->
        plan = Bibliography.plan(data, FilemakerSync.all_plays())
        Enum.each(Bibliography.report(plan), &Mix.shell().info/1)

        if opts[:dry_run] do
          Mix.shell().info("\ndry run, nothing written")
        else
          {:ok, written} = Bibliography.apply_plan(plan)
          Mix.shell().info("\ncreated #{written.entries} entries and #{written.links} links")
        end

      {:error, {file, reason}} ->
        Mix.raise("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end
end
```

- [ ] **Step 5: Add the release function**

In `lib/playcode/release.ex`, after `invite_url/2`:

```elixir
  @doc """
  S4's one-time bibliography import, for a release, which has no mix tasks. Copy the six
  tables onto the machine first (`fly ssh sftp shell`), then:

      bin/playcode rpc 'Playcode.Release.import_bibliography("/tmp/ctce", dry_run: true)'
      bin/playcode rpc 'Playcode.Release.import_bibliography("/tmp/ctce")'
  """
  def import_bibliography(dir, opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    alias Playcode.Import.{Bibliography, FilemakerSync}

    case Bibliography.load(dir) do
      {:ok, data} ->
        plan = Bibliography.plan(data, FilemakerSync.all_plays())
        Enum.each(Bibliography.report(plan), &IO.puts/1)

        if opts[:dry_run] do
          IO.puts("dry run, nothing written")
        else
          {:ok, written} = Bibliography.apply_plan(plan)
          IO.puts("created #{written.entries} entries and #{written.links} links")
        end

      {:error, {file, reason}} ->
        IO.puts("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/mix/tasks_test.exs`
Expected: pass.

- [ ] **Step 7: Refactor while green, then the full gate**

`Release.import_bibliography/2` and the mix task share the report-then-apply shape. A shared helper is fine if it stays shorter than the two copies. Run `mix format && mix compile --warnings-as-errors && mix test`.

- [ ] **Step 8: Commit**

```bash
git commit -m "feat(import): mix playcode.import.bibliography and its release twin

One transaction; a re-run skips plays already imported and reuses entries
by filemaker_id, so a play added later joins the shared editions.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode/import/bibliography.ex lib/mix/tasks/playcode.import.bibliography.ex lib/playcode/release.ex test/mix/tasks_test.exs
```

---

### Task 6: The FileMaker oracle, then the real import on dev

**Files:**
- Create: `test/support/citation_oracle.ex`
- Create: `test/fixtures/filemaker/oracle/regenerate.exs`, and the six files it writes
- Test: `test/playcode/bibliography/oracle_test.exs`
- Modify: `docs/superpowers/specs/2026-10-07-s4-bibliography-design.md`, "Expected result", but only if the dev numbers differ for a reason found in Step 6

**Interfaces:**
- Consumes: `load/1`, `lookups/1`, `record_attrs/2`, `edition_attrs/2`, `editions_by_id/1` (Task 4); `Citation.plain/2` (Task 2); `Entry.named?/1`.
- Produces: `Playcode.CitationOracle.misses(dir)` → `%{ref => [word]}`.

- [ ] **Step 1: Write the sample generator**

`test/fixtures/filemaker/oracle/regenerate.exs`:

```elixir
# Rebuilds the oracle sample in this directory from the git-ignored FileMaker dump: the
# records and modern-edition links below, the links of those records, and the cities and
# publishers they name. Rows are copied byte for byte, so FileMaker's own citation text
# comes with them. Run from the repository root:
#
#     mix run --no-start test/fixtures/filemaker/oracle/regenerate.exs
#
# The ids cover every publication type and every optional field. See "Testing" in
# docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

alias Playcode.Import.FilemakerXml

dump = "doc/ctce_dades"
out = Path.dirname(__ENV__.file)

records =
  ~w(36 40 37 38 1417 1751 43 49 61 62 1024 1435 70 133 84 86 107 115 184 187 193 674 675 113 1420 331 516 94 111 1405)

edition_links = ~w(40 42 26 44 59 65 60 61 52 58 55 957 54 79 69 757)

# Keeps the rows of `file` whose `field` is in `keep`, and rewrites FOUND to match.
keep = fn file, field, keep ->
  xml = File.read!(Path.join(dump, file))
  names = ~r/<FIELD [^>]*NAME="([^"]+)"/ |> Regex.scan(xml, capture: :all_but_first) |> List.flatten()
  index = Enum.find_index(names, &(&1 == field))
  [head, rest] = String.split(xml, "<RESULTSET", parts: 2)
  [_found, rows] = String.split(rest, ">", parts: 2)

  kept =
    ~r{<ROW [^>]*>.*?</ROW>}s
    |> Regex.scan(rows)
    |> List.flatten()
    |> Enum.filter(fn row ->
      cols = ~r{<COL>(.*?)</COL>}s |> Regex.scan(row, capture: :all_but_first) |> List.flatten()
      value = cols |> Enum.at(index, "") |> String.replace(~r{</?DATA>}, "")
      MapSet.member?(keep, value)
    end)

  File.write!(
    Path.join(out, file),
    head <> ~s(<RESULTSET FOUND="#{length(kept)}">) <> Enum.join(kept) <> "</RESULTSET></FMPXMLRESULT>"
  )
end

{:ok, all_links} = FilemakerXml.read(Path.join(dump, "T04_ObraModernaRecomendada.xml"))

editions =
  all_links
  |> Enum.filter(&(&1["_kp_IdObraEdModRecomendada"] in edition_links))
  |> MapSet.new(& &1["_k_IdEdicionModerna"])

keep.("T12.1_BibliografiaSelecta.xml", "_kp_IdBiblioSelecta", MapSet.new(records))
keep.("T12_ObraBibliografiaSelecta.xml", "_k_IdBiblioSelecta", MapSet.new(records))
keep.("T04_ObraModernaRecomendada.xml", "_kp_IdObraEdModRecomendada", MapSet.new(edition_links))
keep.("T04.1_EdModerna.xml", "_kp_IdEdicionModerna", editions)

{:ok, kept_records} = FilemakerXml.read(Path.join(out, "T12.1_BibliografiaSelecta.xml"))
{:ok, kept_editions} = FilemakerXml.read(Path.join(out, "T04.1_EdModerna.xml"))
named = fn field -> MapSet.new(kept_records ++ kept_editions, & &1[field]) end

keep.("T13.1_Ciudad.xml", "_kp_IdCiudad", named.("_k_IdCiudad"))
keep.("T13.2_Editorial.xml", "_kp_IdEditorial", named.("_k_IdEditorial"))

IO.puts("wrote the oracle sample to #{out}")
```

Run: `mix run --no-start test/fixtures/filemaker/oracle/regenerate.exs`
Expected: `wrote the oracle sample to …`, and six `.xml` files in `test/fixtures/filemaker/oracle/`. Check them: `grep -o '<ROW ' test/fixtures/filemaker/oracle/T12.1_BibliografiaSelecta.xml | wc -l` gives 30.

- [ ] **Step 2: Write the failing test**

`test/playcode/bibliography/oracle_test.exs`:

```elixir
defmodule Playcode.Bibliography.OracleTest do
  @moduledoc """
  Every word FileMaker printed in a citation is in ours. The sample is committed; the
  whole dump is git-ignored, so its sweep runs only where it is present.
  """
  use ExUnit.Case, async: true

  alias Playcode.CitationOracle

  test "the committed sample: 30 records and 16 modern-edition links" do
    assert CitationOracle.misses("test/fixtures/filemaker/oracle") == %{}
  end

  @tag :slow
  test "the whole FileMaker dump, where present" do
    if File.dir?("doc/ctce_dades") do
      # 2095's URL access date is a page range typed into the wrong field, with no URL
      # beside it, so it prints nowhere. Curators fix it in admin.
      assert CitationOracle.misses("doc/ctce_dades") == %{"T12:2095" => ["853", "960"]}
    end
  end
end
```

- [ ] **Step 3: Run it and see it fail**

Run: `mix test test/playcode/bibliography/oracle_test.exs`
Expected: `module Playcode.CitationOracle is not available`.

- [ ] **Step 4: Write the oracle**

`test/support/citation_oracle.ex`:

```elixir
defmodule Playcode.CitationOracle do
  @moduledoc """
  Checks the renderer against FileMaker's own citations: for each record, and for each
  modern-edition link, the words FileMaker printed that ours lacks.

  Labels (`Vol.`, `Ed.`, `Tra.`…) and `{Falta …}` placeholders are left out, and letters
  are split from digits because FileMaker glues `London2010`. Neither order nor
  punctuation is compared: test/playcode/bibliography/citation_test.exs pins those.
  """

  alias Playcode.Bibliography.{Citation, Entry, Link}
  alias Playcode.Import.Bibliography

  @labels ~w(vol vols p pp ed eds tra url orig in i acc)

  @doc "`%{ref => [word]}` for every citation that lacks a word FileMaker printed."
  def misses(dir) do
    {:ok, data} = Bibliography.load(dir)
    lookups = Bibliography.lookups(data)
    editions = Bibliography.editions_by_id(data.editions)

    records =
      Enum.flat_map(data.bib_records, fn row ->
        attrs = Bibliography.record_attrs(row, lookups)
        theirs = row["_tc_BibSel_ComposicionExtensa"] || ""

        if theirs != "" and Entry.named?(attrs),
          do: [{"T12:" <> row["_kp_IdBiblioSelecta"], theirs, Citation.plain(struct(Entry, attrs))}],
          else: []
      end)

    links =
      Enum.flat_map(data.edition_links, fn row ->
        theirs = row["w3pub_EdModernaItem"] || ""
        edition = editions[row["_k_IdEdicionModerna"]]

        if theirs != "" and edition do
          entry = struct(Entry, Bibliography.edition_attrs(edition, lookups))
          link = %Link{volume: row["ObraEdMod_Volumen"], pages: row["ObraEdMod_Paginas"]}
          [{"T04:#{row["_k_IdEdicionModerna"]} on #{row["_k_IdObraTitulo"]}", theirs, Citation.plain(entry, link)}]
        else
          []
        end
      end)

    for {ref, theirs, ours} <- records ++ links,
        missing = MapSet.difference(words(theirs), words(ours)),
        MapSet.size(missing) > 0,
        into: %{} do
      {ref, missing |> MapSet.to_list() |> Enum.sort()}
    end
  end

  @doc "The words of a citation, as the oracle compares them."
  def words(text) do
    text
    |> String.replace(~r/\{Falta[^}]*\}/u, " ")
    |> String.replace(~r{</?(?:i|b|em)>}, " ")
    |> String.replace(["<<", ">>"], " ")
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> then(&Regex.scan(~r/[^\W\d_]+|\d+/u, &1))
    |> List.flatten()
    |> Enum.reject(&(&1 in @labels))
    |> MapSet.new()
  end
end
```

- [ ] **Step 5: Run the sample, then the whole dump**

Run: `mix test test/playcode/bibliography/oracle_test.exs`
Expected: the sample passes.

Run: `mix test test/playcode/bibliography/oracle_test.exs --include slow`
Expected: pass. The prototype measured 2,624 of 2,625 records and 938 of 938 links.
- If other refs appear, read each one before acting.
- A missing word FileMaker printed means a mapping or renderer gap: fix it, and add a case to `citation_test.exs` that pins it.
- If it is FileMaker's own slip, add it to the expected map with a comment saying what the slip is.

- [ ] **Step 6: Prove the oracle bites**

1. In `Citation.the_rest/1`, comment out the `public_note` line.
2. Run the sample test. Expected: fails, listing words from a modern-edition note (for example `printed`, `baldwin` on edition 54's link).
3. Restore the line.

- [ ] **Step 7: Import on dev**

Run: `mix playcode.import.bibliography --dry-run 2>&1 | tail -12`

Expected, against the spec's "Expected result" (392 plays, measured 2026-10-07):
- `bibliography: 2043 entries (0 already in Playcode), 2060 links on 102 plays`
- `modern editions: 680 entries (0 already in Playcode), 752 links on 102 plays`

A small difference can come from rules the prototype counted differently. For example, a book whose only title moves to `series` no longer names anything and is skipped as `no_name`. Explain each difference from the skip lists. If the explanation holds, correct the spec's numbers in this task's commit; otherwise fix the code.

Then run `mix playcode.import.bibliography`.
Expected: `created N entries and M links`, matching the dry run.

- [ ] **Step 8: The full gate, then commit**

Run `mix format && mix compile --warnings-as-errors && mix test`.

```bash
git add test/support/citation_oracle.ex test/playcode/bibliography/oracle_test.exs test/fixtures/filemaker/oracle
git commit -m "test(bibliography): FileMaker's own citations as the oracle

Every word FileMaker printed must be in ours: a committed sample of 30
records and 16 modern-edition links, and a slow sweep over the whole dump
where present (one known exception, 2095). Seen red with public_note
dropped.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- test/support/citation_oracle.ex test/playcode/bibliography/oracle_test.exs test/fixtures/filemaker/oracle
```

If you corrected the spec in Step 7, add it to that commit's paths.

---

### Task 7: The admin tab

**Files:**
- Create: `lib/playcode_web/live/admin/play_bibliography_live.ex`
- Modify:
  - `lib/playcode_web/router.ex:161` (route)
  - `lib/playcode/authz.ex:27-29` (`manage_bibliography`)
  - `lib/playcode_web/components/layouts.ex:103-157` (tab and its doc)
  - `lib/playcode_web/play_labels.ex` (labels)
  - `priv/gettext/default.pot` and `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/admin/play_bibliography_live_test.exs`, `test/playcode_web/authorization_test.exs`

**Interfaces:**
- Consumes: Tasks 1-3: `Citation.html/2`, `list_for_play/1`, `link_counts/1`, `plays_for_entry/1`, `search_entries/3`, `fold/1`, `sort_key/1`, `create_entry_for_play/3`, `update_entry/2`, `update_link/2`, `link_entry/3`, `unlink/1`, `get_link!/1`, `change_entry/2`.
- Produces: `PlayLabels.bibliography_kind_label/1` (plural, for headings), `bibliography_kind_options/0` (singular), `pub_type_label/1`, `pub_type_options/0`, `bibliography_language_label/1` (nil → "Language not stated"). Tasks 8 and 9 use the labels.

**Design** (the project asked for a beautiful page that fits with the play's other metadata, 2026-10-07). It uses the same shell as Sources and Places: `max-w-5xl`, DaisyUI, `rounded-box` cards.

| Part | Look |
|---|---|
| Header | Title and one-line explanation on the left; `Add existing` (ghost) and `New entry` (primary) on the right |
| Jump bar | Sticky under the context bar: one chip per kind with its count, linking to its section, and a filter box on the right |
| Form | Bordered card. An amber alert first when the entry is shared. Fieldsets in a grid on the left, and a sticky "As it will be printed" preview in the reading serif on the right, the same type as the public page |
| Groups | `h2` with a count, `h3` per language for translations |
| Rows | Citation in serif with a hanging look. Below it, small badges: type, *Shared · N plays*, siglum, and internal notes with a lock icon. Row actions are icon buttons at 60% opacity, full on hover or focus |
| Empty state | Dashed card with a book icon and one sentence |

- [ ] **Step 1: Write the failing tests**

`test/playcode_web/live/admin/play_bibliography_live_test.exs`:

```elixir
defmodule PlaycodeWeb.Admin.PlayBibliographyLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Bibliography

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp button(view, link, label),
    do: element(view, ~s(#bib-#{link.id} button[aria-label="#{t(label)}"]))

  test "the play has its own Bibliography tab beside Sources", %{conn: conn, play: play} do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/sources")

    assert view
           |> element(~s(a[href="/admin/plays/#{play.id}/bibliography"]), t("Bibliography"))
           |> has_element?()

    {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    assert html =~ t("No bibliography for this play yet.")
  end

  test "a new entry is previewed as printed and saved with this play's own pages", %{
    conn: conn,
    play: play
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> element("#new-entry") |> render_click()

    entry = %{
      kind: "modern_edition",
      pub_type: "book",
      monogr_editors: "Thompson, Ann",
      monogr_title: "Hamlet"
    }

    view |> form("#entry-form", entry: entry, link: %{pages: "1-50"}) |> render_change()
    assert view |> element("#citation-preview") |> render() =~ "Thompson, Ann, ed. <em>Hamlet</em>."

    view |> form("#entry-form", entry: entry, link: %{pages: "1-50"}) |> render_submit()

    assert [{"modern_edition", [{nil, [link]}]}] = Bibliography.list_for_play(play.id)
    assert link.pages == "1-50"
    assert render(view) =~ t("Entry added.")

    assert [%{resource_type: "bibliography_entry"}] =
             Playcode.ActivityLog.list_entries(resource_type: "bibliography_entry")
  end

  test "an entry with no author, editor or title is refused, saying why", %{
    conn: conn,
    play: play
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> element("#new-entry") |> render_click()

    html =
      view
      |> form("#entry-form", entry: %{kind: "criticism", year_text: "2005"})
      |> render_submit()

    assert html =~
             Gettext.dgettext(PlaycodeWeb.Gettext, "errors", "needs an author, an editor or a title")

    assert Bibliography.list_links(play.id) == []
  end

  test "editing a shared entry warns first, and the edit reaches the other play", %{
    conn: conn,
    play: play
  } do
    other = play_fixture()
    link = bibliography_fixture(play, %{"monogr_title" => "Complete Works"})
    {:ok, _} = Bibliography.link_entry(other.id, link.entry_id)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> button(link, "Edit") |> render_click()

    assert view |> element("#entry-editor [role=alert]") |> render() =~ other.code

    view |> form("#entry-form", entry: %{monogr_title: "The Complete Works"}) |> render_submit()

    assert [{"criticism", [{nil, [shared]}]}] = Bibliography.list_for_play(other.id)
    assert shared.entry.monogr_title == "The Complete Works"
  end

  test "an entry another play has is found and added", %{conn: conn, play: play} do
    bibliography_fixture(play_fixture(), %{
      "kind" => "modern_edition",
      "monogr_title" => "The Riverside Shakespeare",
      "monogr_editors" => "Evans, G. Blakemore"
    })

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> element("#add-existing-button") |> render_click()
    view |> form("#entry-search", term: "riverside") |> render_change()
    view |> element("#add-existing li button", t("Add")) |> render_click()

    assert [{"modern_edition", [{nil, [link]}]}] = Bibliography.list_for_play(play.id)
    assert link.entry.monogr_title == "The Riverside Shakespeare"
  end

  test "removing a shared entry keeps it for the other play; removing the last deletes it", %{
    conn: conn,
    play: play
  } do
    other = play_fixture()
    shared = bibliography_fixture(play, %{"monogr_title" => "Shared volume"})
    {:ok, _} = Bibliography.link_entry(other.id, shared.entry_id)
    own = bibliography_fixture(play, %{"monogr_title" => "Own volume"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

    assert view |> button(shared, "Remove") |> render_click() =~
             t("Removed from this play. The other plays keep it.")

    assert [_] = Bibliography.list_links(other.id)

    assert view |> button(own, "Remove") |> render_click() =~
             t("Entry deleted: no other play used it.")

    assert Bibliography.search_entries("Own volume", other.id) == []
  end

  # Review focus 2.
  test "the filter ignores accents and case, and says when nothing matches", %{
    conn: conn,
    play: play
  } do
    bibliography_fixture(play, %{"monogr_author" => "Zúñiga, Ana", "monogr_title" => "Teatro"})
    bibliography_fixture(play, %{"monogr_author" => "Oleza, Joan", "monogr_title" => "Prácticas"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

    html = view |> form("#bibliography-filter", q: "zuniga") |> render_change()
    assert html =~ "Zúñiga, Ana"
    refute html =~ "Oleza, Joan"

    assert view |> form("#bibliography-filter", q: "nadie") |> render_change() =~
             t("Nothing matches the filter.")
  end
end
```

In `test/playcode_web/authorization_test.exs`, add after the places row:

```elixir
    {"/admin/plays/:id/bibliography", :active},
```

- [ ] **Step 2: Run them and see them fail**

Run: `mix test test/playcode_web/live/admin/play_bibliography_live_test.exs test/playcode_web/authorization_test.exs`
Expected: `no route found for GET /admin/plays/…/bibliography`.

- [ ] **Step 3: Route, permission, tab, labels**

- **`lib/playcode_web/router.ex`:** after `live "/plays/:id/places", PlayPlacesLive, :index`, add

```elixir
      live "/plays/:id/bibliography", PlayBibliographyLive, :index
```

- **`lib/playcode/authz.ex`:** add `manage_bibliography` to `@researcher_actions`.
- **`lib/playcode_web/components/layouts.ex`:** after the Sources `<.link>` add

```heex
          <.link
            navigate={~p"/admin/plays/#{@play.id}/bibliography"}
            class={ctx_tab_class(@active_tab == :bibliography)}
          >
            {gettext("Bibliography")}
          </.link>
```

  and add `:bibliography` to the `active_tab` doc list after `:sources`.

- **`lib/playcode_web/play_labels.ex`:** add `alias Playcode.Bibliography.Entry` and these functions, next to the other label groups:

```elixir
  @doc "A kind's heading: the plural, as the bibliography groups it."
  def bibliography_kind_label("modern_edition"), do: gettext("Modern editions")
  def bibliography_kind_label("criticism"), do: gettext("Criticism")
  def bibliography_kind_label("translation"), do: gettext("Translations")
  def bibliography_kind_label("adaptation"), do: gettext("Adaptations")
  def bibliography_kind_label(_other), do: ""

  @doc "The kinds for a form's select: one entry is one of these."
  def bibliography_kind_options do
    [
      {gettext("Modern edition"), "modern_edition"},
      {gettext("Criticism"), "criticism"},
      {gettext("Translation"), "translation"},
      {gettext("Adaptation"), "adaptation"}
    ]
  end

  def pub_type_label("article"), do: gettext("Journal article")
  def pub_type_label("book_section"), do: gettext("Book chapter")
  def pub_type_label("scholarly_edition"), do: gettext("Scholarly edition")
  def pub_type_label("book"), do: gettext("Book")
  def pub_type_label("proceedings"), do: gettext("Conference proceedings")
  def pub_type_label("prologue"), do: gettext("Prologue")
  def pub_type_label("festschrift"), do: gettext("Festschrift")
  def pub_type_label("electronic"), do: gettext("Electronic publication")
  def pub_type_label("thesis"), do: gettext("Doctoral thesis")
  def pub_type_label("collection"), do: gettext("Collection")
  def pub_type_label(_other), do: ""

  def pub_type_options, do: Enum.map(Entry.pub_types(), &{pub_type_label(&1), &1})

  @doc "A translation group's heading."
  def bibliography_language_label(nil), do: gettext("Language not stated")
  def bibliography_language_label(code), do: Play.language_name(code)
```

`PlayLabels` already aliases `Play`. If it does not, add `alias Playcode.Catalogue.Play`.

- [ ] **Step 4: Write the LiveView**

`lib/playcode_web/live/admin/play_bibliography_live.ex`:

```elixir
defmodule PlaycodeWeb.Admin.PlayBibliographyLive do
  @moduledoc """
  A play's bibliography: its links to the corpus-wide entries, grouped as the public page
  shows them. An entry shared with other plays is edited once for all of them, and the
  form says so before anyone saves. Spec: "Admin" in
  docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.
  """
  use PlaycodeWeb, :live_view

  alias Playcode.ActivityLog
  alias Playcode.Bibliography
  alias Playcode.Bibliography.{Citation, Entry, Link}
  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias PlaycodeWeb.PlayLabels

  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :manage_bibliography}}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Bibliography")}")
     |> assign(:play, play)
     |> assign(:play_context, %{play: play, active_tab: :bibliography})
     |> assign(q: "", adding: false, term: "", suggestions: [])
     |> close_form()
     |> load()}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     socket |> assign(:adding, false) |> open_form(:new, %Entry{kind: "criticism"}, %{}, [])}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    link = Bibliography.get_link!(id)

    others =
      link.entry_id
      |> Bibliography.plays_for_entry()
      |> Enum.reject(&(&1.id == link.play_id))

    params = %{"volume" => link.volume, "pages" => link.pages, "note" => link.note}
    {:noreply, socket |> assign(:adding, false) |> open_form(link, link.entry, params, others)}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, close_form(socket)}

  def handle_event("validate", params, socket) do
    link_params = params["link"] || %{}

    changeset =
      socket
      |> form_entry()
      |> Bibliography.change_entry(params["entry"] || %{})
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: "entry"))
     |> assign(:link_params, link_params)
     |> assign(:preview, preview(changeset, link_params))}
  end

  def handle_event("save", params, socket) do
    entry_params = params["entry"] || %{}
    link_params = params["link"] || %{}

    case save(socket.assigns.editing, socket.assigns.play.id, entry_params, link_params) do
      {:ok, link, action} ->
        log(socket, action, "bibliography_entry", link.entry_id)

        message =
          if action == "create", do: gettext("Entry added."), else: gettext("Entry saved.")

        {:noreply, socket |> close_form() |> load() |> put_flash(:info, message)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "entry"))
         |> assign(:link_params, link_params)}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    link = Bibliography.get_link!(id)
    {:ok, outcome} = Bibliography.unlink(link)
    log(socket, "delete", "play_bibliography", link.id)

    message =
      if outcome == :deleted,
        do: gettext("Entry deleted: no other play used it."),
        else: gettext("Removed from this play. The other plays keep it.")

    {:noreply, socket |> close_form() |> load() |> put_flash(:info, message)}
  end

  def handle_event("open_add", _params, socket) do
    {:noreply, socket |> close_form() |> assign(adding: true, term: "", suggestions: [])}
  end

  def handle_event("close_add", _params, socket), do: {:noreply, assign(socket, :adding, false)}

  def handle_event("search", %{"term" => term}, socket) do
    entries = Bibliography.search_entries(term, socket.assigns.play.id)
    counts = Bibliography.link_counts(Enum.map(entries, & &1.id))

    {:noreply,
     assign(socket,
       term: term,
       suggestions: Enum.map(entries, &{&1, Map.get(counts, &1.id, 0)})
     )}
  end

  def handle_event("link", %{"entry" => entry_id}, socket) do
    case Bibliography.link_entry(socket.assigns.play.id, entry_id) do
      {:ok, link} ->
        log(socket, "create", "play_bibliography", link.id)

        {:noreply,
         socket
         |> assign(adding: false, term: "", suggestions: [])
         |> load()
         |> put_flash(:info, gettext("Entry added."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("That entry is already in this play's bibliography."))}
    end
  end

  def handle_event("filter", %{"q" => q}, socket), do: {:noreply, assign(socket, :q, q)}

  defp save(:new, play_id, entry_params, link_params) do
    with {:ok, link} <- Bibliography.create_entry_for_play(play_id, entry_params, link_params),
         do: {:ok, link, "create"}
  end

  defp save(%Link{} = link, _play_id, entry_params, link_params) do
    with {:ok, _entry} <- Bibliography.update_entry(link.entry, entry_params),
         {:ok, link} <- Bibliography.update_link(link, link_params),
         do: {:ok, link, "update"}
  end

  defp load(socket) do
    groups = Bibliography.list_for_play(socket.assigns.play.id)

    entry_ids =
      for {_kind, subgroups} <- groups,
          {_language, links} <- subgroups,
          link <- links,
          do: link.entry_id

    socket
    |> assign(:groups, groups)
    |> assign(:shared, Bibliography.link_counts(entry_ids))
  end

  defp open_form(socket, editing, entry, link_params, others) do
    changeset = Bibliography.change_entry(entry)

    assign(socket,
      editing: editing,
      form: to_form(changeset, as: "entry"),
      link_params: link_params,
      shared_with: others,
      preview: preview(changeset, link_params)
    )
  end

  defp close_form(socket) do
    assign(socket, editing: nil, form: nil, link_params: %{}, shared_with: [], preview: nil)
  end

  defp form_entry(%{assigns: %{editing: %Link{entry: entry}}}), do: entry
  defp form_entry(_socket), do: %Entry{}

  defp preview(changeset, link_params) do
    entry = Ecto.Changeset.apply_changes(changeset)

    if Entry.named?(entry),
      do: Citation.html(entry, %Link{volume: link_params["volume"], pages: link_params["pages"]})
  end

  defp log(socket, action, resource_type, resource_id) do
    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      play_id: socket.assigns.play.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id
    })
  end

  # The groups with only the links whose printed citation contains the filter, compared
  # folded, like the sort.
  defp visible(groups, q) do
    case Bibliography.fold(q) do
      "" ->
        groups

      needle ->
        Enum.flat_map(groups, fn {kind, subgroups} ->
          kept =
            Enum.flat_map(subgroups, fn {language, links} ->
              case Enum.filter(links, &String.contains?(Bibliography.sort_key(&1), needle)) do
                [] -> []
                matching -> [{language, matching}]
              end
            end)

          if kept == [], do: [], else: [{kind, kept}]
        end)
    end
  end

  defp count(subgroups), do: subgroups |> Enum.map(fn {_l, links} -> length(links) end) |> Enum.sum()

  defp language_options, do: Enum.map(Entry.languages(), &{Play.language_name(&1), &1})

  defp internal_notes(link), do: Enum.filter([link.entry.note, link.note], &(&1 not in [nil, ""]))

  defp shared?(shared, link), do: Map.get(shared, link.entry_id, 1) > 1

  defp remove_confirm(shared, link) do
    if shared?(shared, link),
      do: gettext("Remove this entry from this play? The other plays keep it."),
      else: gettext("Delete this entry? No other play uses it.")
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, visible(assigns.groups, assigns.q))

    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Bibliography")}
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            {gettext(
              "Modern editions, criticism, translations and adaptations of this play. An entry shared with other plays is edited once for all of them."
            )}
          </p>
        </div>
        <div :if={is_nil(@editing) and not @adding} class="flex gap-2">
          <button
            id="add-existing-button"
            type="button"
            phx-click="open_add"
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-link-mini" class="size-4" /> {gettext("Add existing")}
          </button>
          <button id="new-entry" type="button" phx-click="new" class="btn btn-primary btn-sm gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("New entry")}
          </button>
        </div>
      </header>

      <nav
        :if={@groups != []}
        aria-label={gettext("Bibliography sections")}
        class="sticky top-0 z-10 -mx-4 mb-6 flex flex-wrap items-center gap-2 border-b border-base-300 bg-base-100/90 px-4 py-2 backdrop-blur-sm"
      >
        <a
          :for={{kind, subgroups} <- @groups}
          href={"#kind-#{kind}"}
          class="badge badge-ghost gap-1.5 py-3 transition hover:badge-primary"
        >
          {PlayLabels.bibliography_kind_label(kind)}
          <span class="font-semibold tabular-nums">{count(subgroups)}</span>
        </a>
        <form id="bibliography-filter" phx-change="filter" phx-submit="filter" class="ml-auto">
          <label class="input input-sm input-bordered flex items-center gap-2">
            <.icon name="hero-magnifying-glass-mini" class="size-4 opacity-50" />
            <input
              type="search"
              name="q"
              value={@q}
              phx-debounce="200"
              placeholder={gettext("Filter")}
              aria-label={gettext("Filter the bibliography")}
              class="grow"
            />
          </label>
        </form>
      </nav>

      <section
        :if={@adding}
        id="add-existing"
        class="mb-6 rounded-box border border-primary/30 bg-base-100 p-5 shadow-md"
      >
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-primary">
            {gettext("Add an entry another play already has")}
          </h2>
          <button
            type="button"
            phx-click="close_add"
            class="btn btn-ghost btn-xs btn-square"
            aria-label={gettext("Close")}
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
          </button>
        </div>
        <form id="entry-search" phx-change="search" phx-submit="search">
          <input
            type="search"
            name="term"
            value={@term}
            phx-debounce="300"
            placeholder={gettext("Author, editor or title")}
            aria-label={gettext("Search the bibliography")}
            class="input input-bordered input-sm w-full"
            autofocus
          />
        </form>
        <ul class="mt-3 divide-y divide-base-300">
          <li :for={{entry, plays} <- @suggestions} class="flex items-start gap-3 py-3">
            <p class="flex-1 font-serif text-[15px] leading-relaxed">{Citation.html(entry)}</p>
            <span class="badge badge-ghost badge-sm whitespace-nowrap">
              {ngettext("1 play", "%{count} plays", plays)}
            </span>
            <button
              type="button"
              phx-click="link"
              phx-value-entry={entry.id}
              class="btn btn-primary btn-xs"
            >
              {gettext("Add")}
            </button>
          </li>
          <li :if={@term != "" and @suggestions == []} class="py-3 text-sm text-base-content/60">
            {gettext("Nothing matches.")}
          </li>
        </ul>
      </section>

      <section
        :if={@editing}
        id="entry-editor"
        class="mb-8 overflow-hidden rounded-box border border-primary/30 bg-base-100 shadow-md"
      >
        <div :if={@shared_with != []} role="alert" class="alert alert-warning rounded-none">
          <.icon name="hero-users-mini" class="size-5" />
          <span>
            {gettext("Shared with %{count} other plays (%{codes}): changes appear on all of them.",
              count: length(@shared_with),
              codes: Enum.map_join(@shared_with, ", ", & &1.code)
            )}
          </span>
        </div>
        <.form
          for={@form}
          id="entry-form"
          phx-change="validate"
          phx-submit="save"
          class="grid gap-6 p-5 lg:grid-cols-[minmax(0,1fr)_20rem]"
        >
          <div class="space-y-5">
            <div class="grid gap-4 sm:grid-cols-3">
              <.input
                field={@form[:kind]}
                type="select"
                label={gettext("Kind")}
                options={PlayLabels.bibliography_kind_options()}
              />
              <.input
                field={@form[:pub_type]}
                type="select"
                label={gettext("Type")}
                prompt={gettext("Not stated")}
                options={PlayLabels.pub_type_options()}
              />
              <.input
                field={@form[:language]}
                type="select"
                label={gettext("Language")}
                prompt={gettext("Not stated")}
                options={language_options()}
              />
            </div>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Article or chapter")}</legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <.input field={@form[:analytic_author]} label={gettext("Author")} />
                <.input field={@form[:analytic_title]} label={gettext("Title")} />
                <.input field={@form[:analytic_editors]} label={gettext("Editors")} />
                <.input field={@form[:analytic_translators]} label={gettext("Translators")} />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Book or journal")}</legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <.input field={@form[:monogr_author]} label={gettext("Author")} />
                <.input field={@form[:monogr_title]} label={gettext("Title")} />
                <.input field={@form[:monogr_editors]} label={gettext("Editors")} />
                <.input field={@form[:monogr_translators]} label={gettext("Translators")} />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Publication")}</legend>
              <div class="grid gap-3 sm:grid-cols-3">
                <.input field={@form[:pub_place]} label={gettext("Place")} />
                <.input field={@form[:publisher]} label={gettext("Publisher")} />
                <.input field={@form[:year_text]} label={gettext("Year")} />
                <.input field={@form[:edition]} label={gettext("Edition")} />
                <.input field={@form[:volume]} label={gettext("Volume")} />
                <.input field={@form[:volumes_total]} label={gettext("Number of volumes")} />
                <.input field={@form[:issue]} label={gettext("Issue")} />
                <.input field={@form[:pages]} label={gettext("Pages")} />
                <.input field={@form[:series]} label={gettext("Series")} />
                <.input field={@form[:original_title]} label={gettext("Original title")} />
                <.input field={@form[:url]} label={gettext("URL")} />
                <.input field={@form[:url_accessed_on]} label={gettext("Accessed on")} />
              </div>
              <div
                :if={Phoenix.HTML.Form.input_value(@form, :kind) == "modern_edition"}
                class="mt-3 grid gap-3 sm:grid-cols-3"
              >
                <.input field={@form[:siglum]} label={gettext("Siglum")} />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("In this play")}</legend>
              <div class="grid gap-3 sm:grid-cols-3">
                <.input
                  id="link_volume"
                  name="link[volume]"
                  value={@link_params["volume"]}
                  label={gettext("Volume")}
                />
                <.input
                  id="link_pages"
                  name="link[pages]"
                  value={@link_params["pages"]}
                  label={gettext("Pages")}
                />
                <.input
                  id="link_note"
                  name="link[note]"
                  value={@link_params["note"]}
                  label={gettext("Internal note")}
                />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Notes")}</legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <.input
                  field={@form[:public_note]}
                  type="textarea"
                  rows="2"
                  label={gettext("Printed note")}
                />
                <.input
                  field={@form[:note]}
                  type="textarea"
                  rows="2"
                  label={gettext("Internal note, for researchers only")}
                />
              </div>
            </fieldset>

            <div class="flex justify-end gap-2">
              <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
            </div>
          </div>

          <aside class="self-start rounded-box bg-base-200/60 p-4 lg:sticky lg:top-16">
            <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/50">
              {gettext("As it will be printed")}
            </h3>
            <p id="citation-preview" class="font-serif text-[15px] leading-relaxed [&_a]:link">
              {@preview || gettext("Fill in an author, an editor or a title.")}
            </p>
          </aside>
        </.form>
      </section>

      <div
        :if={@groups == [] and is_nil(@editing)}
        class="rounded-box border border-dashed border-base-300 py-14 text-center text-base-content/60"
      >
        <.icon name="hero-book-open" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No bibliography for this play yet.")}</p>
      </div>

      <p :if={@groups != [] and @shown == []} class="py-10 text-center text-sm text-base-content/60">
        {gettext("Nothing matches the filter.")}
      </p>

      <section :for={{kind, subgroups} <- @shown} id={"kind-#{kind}"} class="mb-10 scroll-mt-16">
        <h2 class="mb-3 flex items-baseline gap-2 border-b border-base-300 pb-2 text-lg font-semibold">
          {PlayLabels.bibliography_kind_label(kind)}
          <span class="text-sm font-normal tabular-nums text-base-content/50">
            {count(subgroups)}
          </span>
        </h2>
        <div :for={{language, links} <- subgroups} class="mb-4">
          <h3
            :if={kind == "translation"}
            class="mb-1 mt-4 text-xs font-semibold uppercase tracking-wide text-base-content/50"
          >
            {PlayLabels.bibliography_language_label(language)}
          </h3>
          <ol class="space-y-1">
            <li
              :for={link <- links}
              id={"bib-#{link.id}"}
              class="group -mx-3 flex gap-3 rounded-lg px-3 py-2.5 transition hover:bg-base-200/60"
            >
              <div class="min-w-0 flex-1">
                <p class="font-serif text-[15px] leading-relaxed text-base-content [&_a]:link [&_a]:break-all">
                  {Citation.html(link.entry, link)}
                </p>
                <div class="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-base-content/55">
                  <span :if={link.entry.pub_type} class="badge badge-ghost badge-xs">
                    {PlayLabels.pub_type_label(link.entry.pub_type)}
                  </span>
                  <span
                    :if={shared?(@shared, link)}
                    class="badge badge-outline badge-primary badge-xs gap-1"
                  >
                    <.icon name="hero-link-micro" class="size-3" />
                    {gettext("Shared · %{count} plays", count: @shared[link.entry_id])}
                  </span>
                  <span :if={link.entry.siglum} class="badge badge-ghost badge-xs font-mono">
                    {link.entry.siglum}
                  </span>
                  <span :for={note <- internal_notes(link)} class="inline-flex items-center gap-1 italic">
                    <.icon name="hero-lock-closed-micro" class="size-3" />{note}
                  </span>
                </div>
              </div>
              <div class="flex shrink-0 items-start gap-0.5 opacity-60 transition group-hover:opacity-100 focus-within:opacity-100">
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={link.id}
                  class="btn btn-ghost btn-xs btn-square"
                  aria-label={gettext("Edit")}
                >
                  <.icon name="hero-pencil-square-micro" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="remove"
                  phx-value-id={link.id}
                  data-confirm={remove_confirm(@shared, link)}
                  class="btn btn-ghost btn-xs btn-square text-error"
                  aria-label={gettext("Remove")}
                >
                  <.icon name="hero-trash-micro" class="size-4" />
                </button>
              </div>
            </li>
          </ol>
        </div>
      </section>
    </div>
    """
  end
end
```

- [ ] **Step 5: Translations**

Run `mix gettext.extract --merge`, then fill `priv/gettext/es/LC_MESSAGES/default.po`:

| msgid | msgstr |
|---|---|
| Bibliography | Bibliografía |
| Modern editions | Ediciones modernas |
| Criticism | Bibliografía crítica |
| Translations | Traducciones |
| Adaptations | Adaptaciones |
| Modern edition | Edición moderna |
| Translation | Traducción |
| Adaptation | Adaptación |
| Journal article | Artículo de revista |
| Book chapter | Capítulo de libro |
| Scholarly edition | Edición de estudioso |
| Book | Libro |
| Conference proceedings | Actas |
| Festschrift | Homenaje |
| Electronic publication | Publicación electrónica |
| Doctoral thesis | Tesis doctoral |
| Collection | Colección |
| Language not stated | Idioma sin indicar |
| bibliography entry | entrada bibliográfica |
| bibliography link | vínculo bibliográfico |
| Modern editions, criticism, translations and adaptations of this play. An entry shared with other plays is edited once for all of them. | Ediciones modernas, crítica, traducciones y adaptaciones de esta obra. Una entrada compartida con otras obras se edita una vez para todas. |
| Add existing | Añadir existente |
| New entry | Nueva entrada |
| Bibliography sections | Secciones de la bibliografía |
| Filter | Filtrar |
| Filter the bibliography | Filtrar la bibliografía |
| Add an entry another play already has | Añadir una entrada que ya tiene otra obra |
| Author, editor or title | Autor, editor o título |
| Search the bibliography | Buscar en la bibliografía |
| 1 play / %{count} plays | 1 obra / %{count} obras |
| Nothing matches. | No hay coincidencias. |
| Shared with %{count} other plays (%{codes}): changes appear on all of them. | Compartida con %{count} obras más (%{codes}): los cambios aparecen en todas. |
| Kind | Clase |
| Type | Tipo |
| Not stated | Sin indicar |
| Article or chapter | Artículo o capítulo |
| Book or journal | Libro o revista |
| Editors | Editores |
| Translators | Traductores |
| Publication | Publicación |
| Year | Año |
| Edition | Edición |
| Volume | Volumen |
| Number of volumes | Número de volúmenes |
| Issue | Número |
| Pages | Páginas |
| Series | Colección |
| Original title | Título original |
| Accessed on | Consultado el |
| Siglum | Sigla |
| In this play | En esta obra |
| Internal note | Nota interna |
| Notes | Notas |
| Printed note | Nota impresa |
| Internal note, for researchers only | Nota interna, solo para investigadores |
| As it will be printed | Tal como se imprimirá |
| Fill in an author, an editor or a title. | Escribe un autor, un editor o un título. |
| No bibliography for this play yet. | Esta obra aún no tiene bibliografía. |
| Nothing matches the filter. | Nada coincide con el filtro. |
| Shared · %{count} plays | Compartida · %{count} obras |
| Remove | Quitar |
| Remove this entry from this play? The other plays keep it. | ¿Quitar esta entrada de esta obra? Las demás obras la conservan. |
| Delete this entry? No other play uses it. | ¿Borrar esta entrada? Ninguna otra obra la usa. |
| Entry added. | Entrada añadida. |
| Entry saved. | Entrada guardada. |
| Entry deleted: no other play used it. | Entrada borrada: ninguna otra obra la usaba. |
| Removed from this play. The other plays keep it. | Quitada de esta obra. Las demás obras la conservan. |
| That entry is already in this play's bibliography. | Esa entrada ya está en la bibliografía de esta obra. |

Strings that already exist (`Author`, `Title`, `Place`, `Publisher`, `Language`, `Edit`, `Cancel`, `Save`, `Close`, `Add`, `URL`, `Prologue`) keep their translations; check them, do not re-add them. Then:
- Remove every `#, fuzzy` flag you have checked.
- Run the CLAUDE.md `comm` recipe to confirm nothing is missing.

- [ ] **Step 6: Run the tests**

Run: `mix test test/playcode_web/live/admin/play_bibliography_live_test.exs test/playcode_web/authorization_test.exs`
Expected: pass.

- [ ] **Step 7: Prove the filter test bites**

1. In `visible/2`, replace `Bibliography.fold(q)` with `q`.
2. Run the filter test. Expected: it fails on `zuniga`.
3. Restore.

- [ ] **Step 8: Look at it**

1. Run `mix phx.server` and open `/admin/plays/<id>/bibliography` for EMOTHE0010 *Hamlet*, which has real data since Task 6.
2. Check, in light and dark theme and at a phone width:
   - the jump bar sticks
   - the preview sits beside the form on a wide screen and below it on a narrow one
   - long URLs wrap
   - the shared badge shows on the Wells and Taylor edition
3. Fix spacing or contrast that looks off. Keep the classes within DaisyUI and Tailwind, as on the Sources page.

- [ ] **Step 9: Refactor while green, then the full gate**

Run `mix format && mix compile --warnings-as-errors && mix test`.

- [ ] **Step 10: Commit**

```bash
git commit -m "feat(admin): a Bibliography tab for every play

Grouped as the public page shows it, with a jump bar, an accent-blind
filter, a live preview of the printed citation, and a warning before
editing an entry other plays share. Filter test seen red without folding.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode_web/live/admin/play_bibliography_live.ex lib/playcode_web/router.ex lib/playcode/authz.ex lib/playcode_web/components/layouts.ex lib/playcode_web/play_labels.ex priv/gettext test/playcode_web/live/admin/play_bibliography_live_test.exs test/playcode_web/authorization_test.exs
```

---

### Task 8: `/plays/:code`

**Files:**
- Modify: `lib/playcode_web/live/play_show_live.ex`
- Test: `test/playcode_web/live/play_show_live_test.exs`

**Interfaces:**
- Consumes: `Bibliography.list_for_play/1`, `Citation.html/2`, `PlayLabels.bibliography_kind_label/1` and `PlayLabels.bibliography_language_label/1`.

- [ ] **Step 1: Write the failing tests**

Add to `test/playcode_web/live/play_show_live_test.exs`:

```elixir
  describe "the bibliography panel" do
    test "is absent when the play has none", %{conn: conn} do
      play = Playcode.TestFixtures.play_fixture()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      refute has_element?(view, "#meta-bibliography")
      refute has_element?(view, ~s(a[href="#meta-bibliography"]))
    end

    test "lists the citations by kind, with its own sidebar entry, and no researcher's note", %{
      conn: conn
    } do
      play = Playcode.TestFixtures.play_fixture()

      Playcode.TestFixtures.bibliography_fixture(
        play,
        %{
          "monogr_author" => "Oleza, Joan",
          "monogr_title" => "Teatro y prácticas escénicas",
          "public_note" => "Reimpreso en 1990",
          "note" => "Revisar la fecha"
        },
        %{"note" => "Préstamo interbibliotecario"}
      )

      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      section = view |> element("#meta-bibliography") |> render()

      assert section =~ t("Criticism")
      assert section =~ "Oleza, Joan. Teatro y prácticas escénicas."
      assert section =~ "Reimpreso en 1990."
      refute section =~ "Revisar la fecha"
      refute section =~ "Préstamo interbibliotecario"
      assert has_element?(view, ~s(a[href="#meta-bibliography"]), t("Bibliography"))
    end
  end
```

- [ ] **Step 2: Run them and see them fail**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: the second test fails, `selector "#meta-bibliography" did not return any element`.

- [ ] **Step 3: Implement**

In `lib/playcode_web/live/play_show_live.ex`:

1. Add `alias Playcode.Bibliography` and `alias Playcode.Bibliography.Citation` with the other aliases.
2. In `mount/3`, after `statistic = …`, add `bibliography = Bibliography.list_for_play(play.id)`. Pass it on with `build_sections_navigation(play, divisions, bibliography)` and `|> assign(:bibliography, bibliography)`.
3. Change the navigation functions:

```elixir
  defp build_sections_navigation(play, divisions, bibliography) do
    metadata_sections = build_metadata_sections(play, bibliography)
    play_sections = divisions |> Enum.flat_map(&division_navigation_item(&1, 0))

    %{metadata: metadata_sections, play: play_sections}
  end

  defp build_metadata_sections(play, bibliography) do
    base = [%{id: "meta-overview", label: gettext("Overview")}]

    base
    |> maybe_add_section(
      play.historical_time != nil or play.composition_date_from != nil or
        play.composition_date_note != nil,
      "meta-study",
      gettext("Study")
    )
    |> maybe_add_section(play.play_places != [], "meta-places", gettext("Places"))
    |> maybe_add_section(play.sources != [], "meta-sources", gettext("Source"))
    |> maybe_add_section(play.editors != [], "meta-editors", gettext("Editors"))
    |> maybe_add_section(bibliography != [], "meta-bibliography", gettext("Bibliography"))
    |> Kernel.++(build_editorial_note_sections(play.editorial_notes))
  end
```

  If `build_sections_navigation/2` has other callers, add the argument there too: grep for it.

4. After the Places `</section>` and before `<%!-- Editorial notes`, add:

```heex
          <%!-- Bibliography --%>
          <section
            :if={@bibliography != []}
            id="meta-bibliography"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <h2 class="mb-4 text-xs font-semibold uppercase tracking-wide text-base-content/50">
              {gettext("Bibliography")}
            </h2>
            <div
              :for={{kind, subgroups} <- @bibliography}
              id={"meta-bibliography-#{kind}"}
              class="mb-6 scroll-mt-20"
            >
              <h3 class="mb-2 font-semibold text-base-content">
                {PlayLabels.bibliography_kind_label(kind)}
              </h3>
              <div :for={{language, links} <- subgroups}>
                <h4 :if={kind == "translation"} class="mb-1 mt-3 text-xs text-base-content/50">
                  {PlayLabels.bibliography_language_label(language)}
                </h4>
                <ul class="space-y-2">
                  <li
                    :for={link <- links}
                    class="pl-6 -indent-6 font-serif leading-relaxed [&_a]:link [&_a]:break-all"
                  >
                    {Citation.html(link.entry, link)}
                  </li>
                </ul>
              </div>
            </div>
          </section>
```

The `pl-6 -indent-6` pair gives each citation the hanging indent a printed bibliography has.

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode_web/live/play_show_live_test.exs`
Expected: pass.

- [ ] **Step 5: Prove the note test bites**

1. In `Citation.the_rest/1`, temporarily add `with_value(e.note, &sentence/1)`.
2. Run the test. Expected: `refute section =~ "Revisar la fecha"` fails.
3. Remove the line.

- [ ] **Step 6: Refactor while green, then the full gate**

Run `mix format && mix compile --warnings-as-errors && mix test`.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(public): the bibliography on /plays/:code

Its own sidebar entry and section, grouped by kind, hanging-indented.
Researchers' notes never show; the note test was seen red with the note
printed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode_web/live/play_show_live.ex test/playcode_web/live/play_show_live_test.exs
```

---

### Task 9: The static site

**Files:**
- Modify:
  - `lib/playcode/export/static_site/edition.ex` (`:bibliography`)
  - `lib/playcode/export/static_site/components.ex` (`bibliography/1`, rail entry)
  - `lib/playcode/export/static_site/pages/title.html.heex`
  - `lib/playcode/export/static_site/fingerprint.ex:24-33`
  - `priv/static_site/style.css`
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: `Bibliography.list_for_play/1`, `Citation.html/2`, the PlayLabels functions.
- Produces: `%Edition{bibliography: [...]}`.

- [ ] **Step 1: Write the failing test**

Add to `test/playcode/export/static_site_play_test.exs`:

```elixir
  test "the title page lists the bibliography by kind, linked from the contents, without researchers' notes" do
    play = import_tei!(tei(body: @two_acts))

    bibliography_fixture(
      play,
      %{
        "kind" => "modern_edition",
        "monogr_editors" => "Thompson, Ann",
        "monogr_title" => "Hamlet",
        "note" => "Revisar"
      },
      %{"note" => "Préstamo"}
    )

    bibliography_fixture(play, %{
      "kind" => "translation",
      "language" => "fr",
      "monogr_title" => "Hamlet, prince de Danemark"
    })

    dir = generate!([play], all: true)
    title = page(dir, play, "index.html")

    assert texts(title, "#bibliography h3") == ["Modern editions", "Translations"]
    assert texts(title, "#bibliography h4") == ["Français"]
    assert LazyHTML.text(title) =~ "Thompson, Ann, ed. Hamlet."
    refute LazyHTML.text(title) =~ "Revisar"
    refute LazyHTML.text(title) =~ "Préstamo"

    rail =
      dir
      |> page(play, "act-1.html")
      |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
      |> LazyHTML.attribute("href")

    assert "index.html#bibliography" in rail
  end
```

- [ ] **Step 2: Run it and see it fail**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: fails on `#bibliography h3` returning `[]`.

- [ ] **Step 3: Implement**

`edition.ex`:
1. Add `:bibliography` to `defstruct`.
2. Add `Bibliography` to the alias line (`alias Playcode.{Bibliography, Catalogue, PlayContent, Statistics}`).
3. In `load/1`, set `bibliography: Bibliography.list_for_play(id)`, after `play` is loaded.

`components.ex`:
1. Add `alias Playcode.Bibliography.Citation`.
2. Add the component after `places/1`:

```elixir
  attr :groups, :list, required: true

  def bibliography(assigns) do
    ~H"""
    <section :if={@groups != []} id="bibliography" class="bibliography">
      <h2>Bibliography</h2>
      <%= for {kind, subgroups} <- @groups do %>
        <h3>{PlayLabels.bibliography_kind_label(kind)}</h3>
        <%= for {language, links} <- subgroups do %>
          <h4 :if={kind == "translation"}>{PlayLabels.bibliography_language_label(language)}</h4>
          <ul>
            <li :for={link <- links}>{Citation.html(link.entry, link)}</li>
          </ul>
        <% end %>
      <% end %>
    </section>
    """
  end
```

3. In `play_contents/1`, after the Statistics `<li>`:

```heex
      <li :if={@edition.bibliography != []}>
        <a href="index.html#bibliography">Bibliography</a>
      </li>
```

`pages/title.html.heex`: after the Sources `</section>`, add

```heex
    <Components.bibliography groups={@edition.bibliography} />
```

`fingerprint.ex`: add `Playcode.Bibliography` and `Playcode.Bibliography.Citation` to `@modules`. The context decides the grouping and order a page shows, like `Playcode.Places`.

`priv/static_site/style.css`: after the title-page rules, add

```css
.bibliography h3 { font: 600 .9375rem var(--sans); margin: 1.25rem 0 .5rem; }
.bibliography h4 { font: 600 .6875rem/2 var(--sans); text-transform: uppercase; letter-spacing: .08em; color: var(--muted); margin: .75rem 0 .25rem; }
.title-page .bibliography ul { list-style: none; padding-left: 0; }
.bibliography li { padding-left: 1.5rem; text-indent: -1.5rem; margin: 0 0 .4rem; }
.bibliography a { overflow-wrap: anywhere; }
```

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode/export/static_site/fingerprint_test.exs test/playcode/export/static_site_test.exs`
Expected: pass.
- If `fingerprint_test.exs` names a module, add it to `@modules` (if it shapes a page) or to the test's data access list (if it only reads data), and say which in the commit.
- `static_site_test.exs` checks the CSS budget.

- [ ] **Step 5: Refactor while green, then the full gate**

Run `mix format && mix compile --warnings-as-errors && mix test`.

- [ ] **Step 6: Look at it**

1. Run `mix playcode.export.site -o /tmp/s4-site --plays EMOTHE0010_Hamlet --all`. Use the play's real code from `/admin/plays`.
2. Open `/tmp/s4-site/plays/<CODE>/index.html` from disk, in light and dark mode.
3. Check:
   - the hanging indent
   - the rail entry jumps to the section
   - italics render
   - links wrap

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(static-site): the bibliography on the title page

A section after Sources and its own entry in the contents rail; the
renderer and the grouping are fingerprinted, so a change to either
rebuilds every play.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode/export/static_site/edition.ex lib/playcode/export/static_site/components.ex lib/playcode/export/static_site/pages/title.html.heex lib/playcode/export/static_site/fingerprint.ex priv/static_site/style.css test/playcode/export/static_site_play_test.exs
```

---

### Task 10: TEI export

Run `git status` first. If `lib/playcode/export/tei_xml.ex` has changes you did not make, stop and ask the user (see Global Constraints).

**Files:**
- Modify: `lib/playcode/export/tei_xml.ex` (`build_text/3`, new back builders)
- Test: `test/playcode/export/tei_xml_test.exs`, `test/playcode/export/tei_validator_test.exs`

**Interfaces:**
- Consumes: `Bibliography.list_for_play/1`, and the existing `build_inline_content/1` in `tei_xml.ex`.

- [ ] **Step 1: Write the failing tests**

In `test/playcode/export/tei_xml_test.exs`, update the moduledoc's list to mention the bibliography, then add:

```elixir
  describe "bibliography" do
    setup do
      play = import_tei!(tei([]))

      bibliography_fixture(
        play,
        %{
          "kind" => "criticism",
          "pub_type" => "article",
          "language" => "en",
          "analytic_author" => "Barnett, Timothy Brian",
          "analytic_title" => "Lope and <<Tasso>>",
          "monogr_title" => "Bulletin of the Comediantes",
          "year_text" => "2005",
          "volume" => "57",
          "issue" => "2",
          "pages" => "238-294",
          "note" => "Revisar"
        },
        %{"note" => "doi en la nota"}
      )

      bibliography_fixture(
        play,
        %{
          "kind" => "modern_edition",
          "pub_type" => "book_section",
          "analytic_editors" => "Rowe, Nicholas",
          "analytic_title" => "Hamlet",
          "monogr_title" => "The Works",
          "year_text" => "1957-75",
          "volumes_total" => "6",
          "volume" => "1",
          "siglum" => "ROWE1",
          "public_note" => "Printed by Tonson",
          "url" => "https://example.org/rowe"
        },
        %{"volume" => "5", "pages" => "2366-2466"}
      )

      bibliography_fixture(play, %{
        "kind" => "adaptation",
        "pub_type" => nil,
        "monogr_author" => nil,
        "monogr_title" => "Solo un título",
        "url" => ". http://emothe.uv.es/x.php"
      })

      %{play: Playcode.Catalogue.get_play!(play.id), xml: export_tei(play)}
    end

    test "each kind is a listBibl in back, in display order", %{xml: xml} do
      assert [{%{"type" => "bibliografia"}, _text}] = xml_elements(xml, "div", within: "back")

      assert xml |> xml_elements("listBibl") |> Enum.map(&elem(&1, 0)) == [
               %{"type" => "ediciones_modernas"},
               %{"type" => "critica"},
               %{"type" => "adaptaciones"}
             ]
    end

    test "an article: analytic level, journal title, issue and a dated imprint", %{xml: xml} do
      assert [
               %{"type" => "seccion_libro"},
               %{"type" => "articulo_revista", "xml:lang" => "en"},
               %{}
             ] = xml |> xml_elements("biblStruct") |> Enum.map(&elem(&1, 0))

      assert {%{"level" => "a"}, "Lope and Tasso"} in xml_elements(xml, "title", within: "analytic")
      assert "Tasso" in xml_texts(xml, "emph", within: "analytic")
      assert {%{"level" => "j"}, "Bulletin of the Comediantes"} in xml_elements(xml, "title", within: "monogr")
      assert {%{"unit" => "issue"}, "2"} in xml_elements(xml, "biblScope")
      assert {%{"when" => "2005"}, "2005"} in xml_elements(xml, "date", within: "imprint")
    end

    test "a modern edition: the play's own volume and pages, siglum, volumes, note and URL", %{
      xml: xml
    } do
      scopes = xml_elements(xml, "biblScope")
      assert {%{"unit" => "volume"}, "5"} in scopes
      assert {%{"unit" => "page"}, "2366-2466"} in scopes
      refute {%{"unit" => "volume"}, "1"} in scopes

      assert {%{"type" => "siglum"}, "ROWE1"} in xml_elements(xml, "idno", within: "back")
      assert xml_texts(xml, "extent", within: "back") == ["6 vols."]
      assert {%{"target" => "https://example.org/rowe"}, ""} in xml_elements(xml, "ptr")
      assert xml_texts(xml, "note", within: "back") == ["Printed by Tonson"]

      # A range of years is no single date: the text stays, @when does not.
      assert {%{}, "1957-75"} in xml_elements(xml, "date", within: "imprint")
    end

    # Review focus 5.
    test "an imprint with nothing known is still schema-shaped, and a stray URL gives no ptr", %{
      xml: xml
    } do
      assert {%{}, ""} in xml_elements(xml, "date", within: "imprint")
      refute Enum.any?(xml_elements(xml, "ptr"), fn {attrs, _} -> attrs["target"] =~ "emothe" end)
    end

    test "researchers' notes stay out of the file", %{xml: xml} do
      refute xml =~ "Revisar"
      refute xml =~ "doi en la nota"
    end

    # The fixpoint test in tei_roundtrip_test.exs re-imports under a new code, which makes
    # a new play. This one re-imports in place, as a curator would.
    test "re-importing the export in place keeps the bibliography and exports the same file", %{
      play: play,
      xml: xml
    } do
      reimported = import_tei!(xml)

      assert reimported.id == play.id
      assert export_tei(reimported) == xml
    end
  end
```

In `test/playcode/export/tei_validator_test.exs`, inside `describe "validate/1"`, add:

```elixir
    test "a bibliography with every publication type exports as schema-valid TEI" do
      {:ok, play} = TeiParser.import_file(@fixture_file)

      for type <- Playcode.Bibliography.Entry.pub_types() do
        Playcode.TestFixtures.bibliography_fixture(play, %{
          "pub_type" => type,
          "language" => "es",
          "analytic_author" => "Autor, A",
          "analytic_title" => "Capítulo <<en cursiva>>",
          "monogr_title" => "Libro",
          "monogr_editors" => "Editor, E",
          "monogr_translators" => "Traductor, T",
          "pub_place" => "Madrid",
          "publisher" => "Cátedra",
          "year_text" => "1957-75",
          "volume" => "2",
          "issue" => "3",
          "pages" => "1-20",
          "volumes_total" => "4",
          "edition" => "2nd",
          "original_title" => "Original",
          "series" => "Serie",
          "url" => "https://example.org",
          "url_accessed_on" => "2020-01-01",
          "public_note" => "Nota impresa"
        })
      end

      Playcode.TestFixtures.bibliography_fixture(
        play,
        %{
          "kind" => "modern_edition",
          "pub_type" => "book_section",
          "analytic_editors" => "Rowe, Nicholas",
          "analytic_title" => "Hamlet",
          "siglum" => "ROWE1"
        },
        %{"volume" => "5", "pages" => "1-9"}
      )

      Playcode.TestFixtures.bibliography_fixture(play, %{
        "kind" => "adaptation",
        "pub_type" => nil,
        "monogr_title" => "Solo un título"
      })

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert TeiValidator.validate(xml) == {:ok, :valid}
    end
```

- [ ] **Step 2: Run them and see them fail**

Run: `mix test test/playcode/export/tei_xml_test.exs`
Expected: the bibliography tests fail. `listBibl` returns `[]`.

- [ ] **Step 3: Implement**

In `lib/playcode/export/tei_xml.ex`, change `build_text/3`'s last child from `element(:back)` to `build_back(Playcode.Bibliography.list_for_play(play.id))`, and add a section before `# --- Text ---`:

```elixir
  # --- Back: the bibliography (S4) ---

  @list_types %{
    "modern_edition" => "ediciones_modernas",
    "criticism" => "critica",
    "translation" => "traducciones",
    "adaptation" => "adaptaciones"
  }

  # FileMaker's own type names (T12.11), as the corpus spells its other types in Spanish.
  @bibl_types %{
    "article" => "articulo_revista",
    "book_section" => "seccion_libro",
    "scholarly_edition" => "edicion_estudioso",
    "book" => "libro",
    "proceedings" => "acta",
    "prologue" => "prologo",
    "festschrift" => "homenaje",
    "electronic" => "publicacion_electronica",
    "thesis" => "tesis_doctorado",
    "collection" => "coleccion"
  }

  defp build_back([]), do: element(:back)

  defp build_back(groups) do
    element(:back, [
      element(
        :div,
        %{type: "bibliografia"},
        Enum.map(groups, fn {kind, subgroups} ->
          element(
            :listBibl,
            %{type: @list_types[kind]},
            for({_language, links} <- subgroups, link <- links, do: build_bibl_struct(link))
          )
        end)
      )
    ])
  end

  # In the order TEI requires. The entry's `note` and the link's are for researchers and
  # never leave Playcode: this file is published with the static site.
  defp build_bibl_struct(%{entry: e} = link) do
    attrs =
      %{"type" => @bibl_types[e.pub_type], "xml:lang" => e.language}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    element(
      :biblStruct,
      attrs,
      [
        build_analytic(e),
        build_monogr(e, link),
        if(filled?(e.series),
          do:
            element(:series, [element(:title, %{level: "s"}, build_inline_content(e.series))])
        ),
        if(filled?(e.public_note), do: element(:note, build_inline_content(e.public_note))),
        # ponytail: only an http(s) address is a valid target; the FileMaker strays
        # (". http://…") stay in the database for curators to clean.
        if(filled?(e.url) and String.trim(e.url) =~ ~r{\Ahttps?://\S+\z}i,
          do: element(:ptr, %{target: String.trim(e.url)})
        )
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    )
  end

  defp build_analytic(e) do
    if Enum.any?(
         [e.analytic_author, e.analytic_title, e.analytic_editors, e.analytic_translators],
         &filled?/1
       ) do
      element(
        :analytic,
        Enum.reject(
          bibl_people(e.analytic_author, e.analytic_editors, e.analytic_translators) ++
            [
              if(filled?(e.analytic_title),
                do: element(:title, %{level: "a"}, build_inline_content(e.analytic_title))
              )
            ],
          &is_nil/1
        )
      )
    end
  end

  defp build_monogr(e, link) do
    volume = if filled?(link.volume), do: link.volume, else: e.volume
    pages = if filled?(link.pages), do: link.pages, else: e.pages
    level = if e.pub_type == "article", do: "j", else: "m"

    element(
      :monogr,
      Enum.reject(
        bibl_people(e.monogr_author, e.monogr_editors, e.monogr_translators) ++
          [
            element(:title, %{level: level}, build_inline_content(e.monogr_title)),
            if(filled?(e.original_title),
              do: element(:title, %{type: "original"}, build_inline_content(e.original_title))
            ),
            if(filled?(e.siglum), do: element(:idno, %{type: "siglum"}, e.siglum)),
            if(filled?(e.edition), do: element(:edition, e.edition)),
            build_imprint(e),
            if(filled?(e.volumes_total), do: element(:extent, "#{e.volumes_total} vols.")),
            bibl_scope("volume", volume),
            bibl_scope("issue", e.issue),
            bibl_scope("page", pages)
          ],
        &is_nil/1
      )
    )
  end

  defp bibl_people(author, editors, translators) do
    [
      if(filled?(author), do: element(:author, build_inline_content(author))),
      if(filled?(editors), do: element(:editor, editors)),
      if(filled?(translators), do: element(:editor, %{role: "translator"}, translators))
    ]
  end

  defp build_imprint(e) do
    year = if filled?(e.year_text), do: String.trim(e.year_text)

    children =
      Enum.reject(
        [
          if(filled?(e.pub_place), do: element(:pubPlace, e.pub_place)),
          if(filled?(e.publisher), do: element(:publisher, e.publisher)),
          if(year,
            do: element(:date, if(year =~ ~r/^\d{4}$/, do: %{when: year}, else: %{}), year)
          ),
          if(filled?(e.url_accessed_on),
            do: element(:date, %{type: "access"}, e.url_accessed_on)
          )
        ],
        &is_nil/1
      )

    # The schema needs something inside an <imprint>.
    element(:imprint, if(children == [], do: [element(:date)], else: children))
  end

  defp bibl_scope(unit, value),
    do: if(filled?(value), do: element(:biblScope, %{unit: unit}, value))

  defp filled?(value), do: is_binary(value) and String.trim(value) != ""
```

`build_inline_content(nil)` returns `""`, so a missing monograph title writes `<title level="m"/>`, which the schema accepts.

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode/export/tei_xml_test.exs test/playcode/tei_roundtrip_test.exs`
Expected: pass. The round-trip suite must stay green: plays with no bibliography still export `<back/>`.

Run: `mix test test/playcode/export/tei_validator_test.exs --include slow`
Expected: pass.
- If the schema rejects something, the error names the element. Fix the order or the content model, not the test.
- `monogr` order: authors and editors, titles, idno, edition, imprint, extent and biblScope.
- `biblStruct` order: analytic, monogr, series, note, ptr.

- [ ] **Step 5: Refactor while green, then the full gate**

Run `mix format && mix compile --warnings-as-errors && mix test`. Then run `mix test --include slow` once, since the corpus sweep exports every fixture.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(tei): write the bibliography into <back>

One listBibl per kind, biblStruct in schema order, FileMaker's type
names. Researchers' notes are never written; only http(s) addresses
become ptr. Re-importing the export in place keeps the bibliography.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- lib/playcode/export/tei_xml.ex test/playcode/export/tei_xml_test.exs test/playcode/export/tei_validator_test.exs
```

---

### Task 11: Documentation

**Files:**
- Modify:
  - `CLAUDE.md` — only the S4-related lines, and commit with `git commit -p` or explicit hunks, because the file holds the user's own uncommitted changes
  - `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`
  - `docs/superpowers/specs/2026-10-07-s4-bibliography-design.md` (status line)

- [ ] **Step 1: CLAUDE.md**

- **Project Structure:** add `bibliography.ex` and `bibliography/{entry,link,citation}.ex` under `lib/playcode/`; `import/filemaker_xml.ex` and `import/bibliography.ex`; `play_bibliography_live.ex` under admin.
- **Database Schema:** a bullet for `bibliography_entries` (corpus-wide, `filemaker_id`, `note` internal, `public_note` printed) and `play_bibliography` (per-play `volume`, `pages`, `note`, `origin`), and that an entry update moves every linked play.
- **Routes:** `GET /admin/plays/:id/bibliography - A play's bibliography (:manage_bibliography)`.
- **What Has Been Implemented:** an `[x]` entry for S4, naming the spec. Correct the "FileMaker import (S3-S8)" line so it no longer lists bibliography as open.
- **Getting Started:** `mix playcode.import.bibliography [--dry-run]` after the FileMaker sync commands.

- [ ] **Step 2: Roadmap and spec**

- **The slices roadmap:** S4's row and section header become "done", with the date of Task 10's commit and the commit range of Tasks 1-10.
- **The spec's status line:** "implemented", with the same date.

- [ ] **Step 3: Commit**

```bash
git commit -m "docs: S4 bibliography is built

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- docs/superpowers/plans/2026-08-01-filemaker-import-slices.md docs/superpowers/specs/2026-10-07-s4-bibliography-design.md
```

Commit `CLAUDE.md` separately, with only your hunks staged: `git add -p CLAUDE.md`, then `git commit -m "…" ` without `-a`. Show the user the staged diff before committing it.
