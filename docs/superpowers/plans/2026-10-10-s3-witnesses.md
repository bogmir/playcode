# S3 Witnesses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A play's witnesses (manuscripts and early printings) imported once from FileMaker `T03`, edited on a Witnesses admin tab, written to and read from TEI `sourceDesc/listWit`, and printed on `/plays/:code` and the static site the way emothe.uv.es prints them.

**Architecture:** One table, `play_witnesses`, behind one context, `Playcode.Witnesses`, which also holds the one renderer (`parts/1`, `plain/1`, `html/1`) and the TEI helpers (`xml_id/1`, `tei_type/1`, `type_from_tei/2`). The FileMaker import (`Playcode.Import.Witnesses` + `mix playcode.import.witnesses`) and the admin page mirror S4's bibliography; the TEI parser and exporter gain a `listWit` reader and writer beside `sourceDesc/bibl`.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 LiveView 1.1, Ecto + PostgreSQL, Saxy (TEI and FMPXMLRESULT parsing), XmlBuilder (TEI export), HEEx (static site), ExUnit with `Phoenix.LiveViewTest` and `LazyHTML`.

**Spec:** `docs/superpowers/specs/2026-10-10-s3-witnesses-design.md` (read it first; this plan argues from it). Model it is built on: `docs/superpowers/specs/2026-10-07-s4-bibliography-design.md`.

## Global Constraints

- Branch `s3-witnesses`; never commit to `main`.
- TDD for every change, in CLAUDE.md's order: failing test, watch it fail, smallest implementation, watch it pass, **refactor while green**, then `mix test` (the whole suite).
- `mix format` after every task; `mix compile --warnings-as-errors` before every commit.
- Run mix plainly (`mix test`, never `export PATH=… && mix test`).
- Test through the outermost API (CLAUDE.md, "Test behaviour through the outermost API"): LiveViews with `live/2`/`form/3`, mix tasks with `Mix.Task.rerun/2`, TEI as round trips with `test/support/import_helpers.ex`; read back through contexts, never `Repo`.
- Select in tests by visible text (`t/1`) or `aria-label`, never `phx-click` or CSS classes.
- No new dependencies. No HTML library (FileMaker values are plain text).
- Every custom changeset message is hand-added to `priv/gettext/errors.pot` and `priv/gettext/es/LC_MESSAGES/errors.po` (`error_translations_test.exs` fails otherwise).
- After `mix gettext.extract --merge`, every new Spanish entry is translated and no entry is left `fuzzy` (`spanish_translations_test.exs` fails otherwise).
- The static site is in English; admin and `/plays/:code` go through gettext (Spanish).
- `Archivo:` is FileMaker's label and is not translated (spec, "The renderer").
- Never print `siglum` or `witness_type` publicly (spec, "Where it shows").
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

The inputs the spec implies that a task's happy path would not exercise, most likely first. Each has its test in the task named.

1. **A siglum that is not an XML name** (`1623b`, `Q 1`): the export must still validate, with `n` verbatim and a prefixed `xml:id`. Pinned in Task 2 (`xml_id/1`) and Task 3 (round trip, schema check).
2. **A play with witnesses and no sources**: `sourceDesc` must not hold the empty `<p/>` before `listWit`, or the schema fails. Pinned in Task 3.
3. **FileMaker values with line breaks and doubled spaces** (`Sieur du\nLimodin`, `COMEDIES,  HISTORIES`): one line, collapsed. Pinned in Task 2 and in Task 4's printed lines.
4. **A title holding `<<…>>`** (2 FileMaker records): the whole title is italic, no nested markers. Pinned in Task 2.
5. **A TEI `listWit` repeating a siglum, or naming one the play already has** (a hand-typed witness, a modern edition): the import skips it and goes on, instead of failing on the unique index. Pinned in Task 3.

---

## File map

| File | Task | Responsibility |
|---|---|---|
| `lib/playcode/import/bibliography.ex` | 0 | drop FileMaker's test siglum `TES2` (`T04:34`) |
| `priv/repo/migrations/20261010120000_create_play_witnesses.exs` | 1 | table, indexes, content trigger |
| `lib/playcode/witnesses/witness.ex` | 1 | schema, changeset, `types/0` |
| `lib/playcode/witnesses.ex` | 1, 2 | context: list, get, create, update, delete, move, `taken_sigla/1`; renderer; TEI helpers |
| `lib/playcode/catalogue/play.ex`, `lib/playcode/catalogue.ex` | 1 | `has_many :witnesses`, preloaded by `with_all/2` |
| `lib/playcode/activity_log/entry.ex` | 1 | resource type `play_witness` |
| `lib/playcode/export/tei_xml.ex` | 3 | `listWit` writer |
| `lib/playcode/import/tei_parser.ex` | 3 | `listWit` reader, re-import reset, preview counts |
| `lib/playcode/export/static_site/fingerprint.ex` | 3 | fingerprint `Playcode.Witnesses` |
| `test/fixtures/filemaker/witnesses/` | 4 | `regenerate.exs` + the two-table sample it writes |
| `lib/playcode/import/witnesses.ex` | 4 | FileMaker import: load, plan, apply, report |
| `lib/mix/tasks/playcode.import.witnesses.ex`, `lib/playcode/release.ex` | 4 | entry points |
| `lib/playcode_web/live/admin/play_witnesses_live.ex` | 5 | the Witnesses tab |
| `lib/playcode_web/router.ex`, `lib/playcode_web/components/layouts.ex`, `lib/playcode_web/play_labels.ex`, `lib/playcode_web/live/admin/activity_log_live.ex` | 5 | route, tab, type labels, log label |
| `lib/playcode_web/live/play_show_live.ex` | 6 | `#meta-witnesses` |
| `lib/playcode/export/static_site/components.ex`, `pages/title.html.heex` | 6 | Witnesses section and rail entry |
| `CLAUDE.md`, the roadmap, the spec | 7 | docs |

---

### Task 0: Drop FileMaker's test siglum `TES2`

**Files:**
- Modify: `lib/playcode/import/bibliography.ex` (module attributes near line 58; `edition_attrs/2` near line 300)
- Test: `test/playcode/import/bibliography_test.exs`

**Interfaces:**
- Consumes: `Playcode.Import.Bibliography.edition_attrs(row, lookups)` (public, exists)
- Produces: nothing new

`T04:34` is Frenk Alatorre's *Comedias* (1982), a real edition on EMOTHE0013; its siglum `TES2` is FileMaker test data (spec, "Also in this slice: TES2").

- [ ] **Step 1: Write the failing test** — append to `test/playcode/import/bibliography_test.exs`, before the final `end`:

```elixir
  # T04:34 is Frenk Alatorre's Comedias (1982), a real edition: only its siglum, "TES2", is
  # FileMaker test data (docs/superpowers/specs/2026-10-10-s3-witnesses-design.md).
  test "FileMaker's test siglum on a real edition is dropped, and a real one is kept" do
    no_lookups = %{cities: %{}, publishers: %{}}
    row = %{"_kp_IdEdicionModerna" => "34", "EdiMod_Titulo" => "Comedias", "EdiMod_Siglas" => "TES2"}

    assert %{siglum: nil, monogr_title: "Comedias"} = Bibliography.edition_attrs(row, no_lookups)

    assert %{siglum: "RSC"} =
             Bibliography.edition_attrs(%{row | "EdiMod_Siglas" => "RSC"}, no_lookups)
  end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/playcode/import/bibliography_test.exs`
Expected: 1 failure, `match (=) failed` with `siglum: "TES2"` on the left side.

- [ ] **Step 3: Write the smallest implementation**

In `lib/playcode/import/bibliography.ex`, after `@test_editions ~w(9 147)` add:

```elixir
  # T04.1 sigla that are FileMaker's test data on a real edition, by edition id.
  @test_sigla %{"34" => "TES2"}
```

In `edition_attrs/2`, replace `siglum: value(row, "EdiMod_Siglas"),` with `siglum: siglum(row),` and add, next to the other private helpers near `level/2`:

```elixir
  defp siglum(row) do
    siglum = value(row, "EdiMod_Siglas")
    if @test_sigla[row["_kp_IdEdicionModerna"]] == siglum, do: nil, else: siglum
  end
```

- [ ] **Step 4: Run it and watch it pass**

Run: `mix test test/playcode/import/bibliography_test.exs test/playcode/bibliography/oracle_test.exs`
Expected: all pass (the oracle never compares sigla; FileMaker never printed them).

- [ ] **Step 5: Refactor while green** — the helper sits beside `place_and_publisher/2`; nothing else to fold. Re-run Step 4's command.

- [ ] **Step 6: Clear it on dev**, where the import already ran and a re-run skips EMOTHE0013 as already imported:

Run:
```bash
PGPASSWORD=postgres psql -h localhost -U postgres -d playcode_dev -Atc "select filemaker_id, siglum from bibliography_entries where filemaker_id = 'T04:34'"
mix run -e 'e = Playcode.Repo.get_by!(Playcode.Bibliography.Entry, filemaker_id: "T04:34"); {:ok, _} = Playcode.Bibliography.update_entry(e, %{siglum: nil})'
PGPASSWORD=postgres psql -h localhost -U postgres -d playcode_dev -Atc "select filemaker_id, coalesce(siglum, '(none)') from bibliography_entries where filemaker_id = 'T04:34'"
```
Expected: `T04:34|TES2`, then `T04:34|(none)`. If the dev server holds port 4000 and `mix run` fails to start the endpoint, run the same expression in the running server's IEx instead.

- [ ] **Step 7: Format, full suite, commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
git add lib/playcode/import/bibliography.ex test/playcode/import/bibliography_test.exs
git commit -m "fix(import): drop FileMaker's test siglum TES2 from a real modern edition

T04:34 is Frenk Alatorre's Comedias (1982) on EMOTHE0013; its siglum TES2 is
test data. Cleared on dev by hand, since a re-run skips the play.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: The witnesses table and context

**Files:**
- Create: `priv/repo/migrations/20261010120000_create_play_witnesses.exs`
- Create: `lib/playcode/witnesses/witness.ex`
- Create: `lib/playcode/witnesses.ex`
- Modify: `lib/playcode/catalogue/play.ex` (associations, near line 85), `lib/playcode/catalogue.ex` (`with_all/2`, near line 447, and its aliases)
- Modify: `lib/playcode/activity_log/entry.ex` (`@resource_types`, line 16)
- Modify: `priv/gettext/errors.pot`, `priv/gettext/es/LC_MESSAGES/errors.po`
- Test: `test/playcode/witnesses_test.exs` (create), `test/playcode/content_version_test.exs`

**Interfaces:**
- Produces:
  - `Playcode.Witnesses.Witness` — schema `play_witnesses`; fields `siglum title normalized_title attribution pub_place publisher date format witness_type shelfmark note position origin filemaker_id play_id`; `types/0 :: [String.t()]`; `changeset/2`.
  - `Playcode.Witnesses.list_for_play(play_id) :: [Witness.t()]` by position.
  - `get_witness(play_id, id) :: Witness.t() | nil`.
  - `change_witness(witness, attrs \\ %{}) :: Ecto.Changeset.t()`.
  - `create_witness(attrs, base \\ %Witness{}) :: {:ok, Witness.t()} | {:error, Ecto.Changeset.t()}` — appends; `attrs` carry `play_id`; `base` lets the import set `filemaker_id`.
  - `update_witness(witness, attrs)`, `delete_witness(witness)`, `move_witness(witness, :up | :down) :: :ok`.
  - `taken_sigla(play_id) :: MapSet.t(String.t())` — sigla of the play's witnesses and of its linked modern editions.
  - `Play.witnesses` preloaded in position order by `Catalogue.get_play_with_all!/2` and `get_play_by_code_with_all!/2`.

- [ ] **Step 1: Write the failing tests** — create `test/playcode/witnesses_test.exs`:

```elixir
defmodule Playcode.WitnessesTest do
  @moduledoc """
  A play's witnesses through `Playcode.Witnesses`: order, validation, scoping, and the sigla
  a TEI import must leave alone. Spec: docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Witnesses

  defp witness!(play, attrs) do
    {:ok, witness} = Witnesses.create_witness(Map.put(attrs, "play_id", play.id))
    witness
  end

  defp sigla(play), do: play.id |> Witnesses.list_for_play() |> Enum.map(& &1.siglum)

  describe "a play's witnesses" do
    test "a new witness goes last, whatever position it is given" do
      play = play_fixture()
      witness!(play, %{"siglum" => "Q1", "title" => "Uno"})
      witness!(play, %{"siglum" => "Q2", "title" => "Dos", "position" => 0})

      assert sigla(play) == ["Q1", "Q2"]
    end

    test "moving swaps a witness with its neighbour; past either end nothing moves" do
      play = play_fixture()
      [q1, q2, q3] = for s <- ~w(Q1 Q2 Q3), do: witness!(play, %{"siglum" => s, "title" => s})

      assert :ok = Witnesses.move_witness(q3, :up)
      assert sigla(play) == ["Q1", "Q3", "Q2"]

      assert :ok = Witnesses.move_witness(q1, :up)
      assert :ok = Witnesses.move_witness(q2, :down)
      assert sigla(play) == ["Q1", "Q3", "Q2"]
    end

    test "a deleted witness leaves no tie behind it" do
      play = play_fixture()
      [_q1, q2, _q3] = for s <- ~w(Q1 Q2 Q3), do: witness!(play, %{"siglum" => s, "title" => s})
      {:ok, _} = Witnesses.delete_witness(q2)
      witness!(play, %{"siglum" => "Q4", "title" => "Q4"})

      assert sigla(play) == ["Q1", "Q3", "Q4"]
    end

    test "a witness needs a title, a normalised title or a note" do
      play = play_fixture()

      assert {:error, changeset} =
               Witnesses.create_witness(%{"play_id" => play.id, "siglum" => "Q1", "format" => "4º"})

      assert "needs a title, a normalised title or a note" in errors_on(changeset).title

      for field <- ~w(title normalized_title note) do
        assert {:ok, _} = Witnesses.create_witness(%{"play_id" => play.id, field => "Algo"})
      end
    end

    test "a siglum is the play's own: unique within it, free in another" do
      play = play_fixture()
      witness!(play, %{"siglum" => "Q1", "title" => "Uno"})

      assert {:error, changeset} =
               Witnesses.create_witness(%{"play_id" => play.id, "siglum" => "Q1", "title" => "Otro"})

      assert "is already used by another witness of this play" in errors_on(changeset).siglum

      assert {:ok, _} =
               Witnesses.create_witness(%{
                 "play_id" => play_fixture().id,
                 "siglum" => "Q1",
                 "title" => "Otro"
               })
    end

    test "a witness id from the browser resolves only to this play's" do
      play = play_fixture()
      mine = witness!(play, %{"title" => "Mío"})
      theirs = witness!(play_fixture(), %{"title" => "Ajeno"})

      assert Witnesses.get_witness(play.id, mine.id).id == mine.id

      for id <- [theirs.id, Ecto.UUID.generate(), "not-an-id"] do
        assert Witnesses.get_witness(play.id, id) == nil, inspect(id)
      end
    end

    test "the sigla a TEI import must leave alone: the play's witnesses' and its editions'" do
      play = play_fixture()
      witness!(play, %{"siglum" => "Q1", "title" => "Uno"})
      witness!(play, %{"title" => "Sin sigla"})

      bibliography_fixture(play, %{
        "kind" => "modern_edition",
        "monogr_title" => "Chief Pre-Shakespearean Dramas",
        "siglum" => "ADA"
      })

      bibliography_fixture(play_fixture(), %{
        "kind" => "modern_edition",
        "monogr_title" => "Medieval Drama",
        "siglum" => "BEV"
      })

      assert Witnesses.taken_sigla(play.id) == MapSet.new(["Q1", "ADA"])
    end

    test "the play's pages read its witnesses in order" do
      play = play_fixture()
      for s <- ~w(Q2 Q1), do: witness!(play, %{"siglum" => s, "title" => s})

      assert play.id |> Playcode.Catalogue.get_play_with_all!() |> Map.fetch!(:witnesses) |> Enum.map(& &1.siglum) ==
               ["Q2", "Q1"]
    end
  end
end
```

And in `test/playcode/content_version_test.exs`, inside the `edits` keyword list of "every edit to the text, cast, credits, notes or places moves the play", after the `bibliography:` line, add:

```elixir
      witness: fn ->
        Playcode.Witnesses.create_witness(%{play_id: play.id, siglum: "Q1", title: "Q1"})
      end,
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/witnesses_test.exs test/playcode/content_version_test.exs`
Expected: compilation error, `module Playcode.Witnesses is not available` (or `undefined function`).

- [ ] **Step 3: Write the smallest implementation**

Create `priv/repo/migrations/20261010120000_create_play_witnesses.exs`:

```elixir
defmodule Playcode.Repo.Migrations.CreatePlayWitnesses do
  @moduledoc """
  A play's witnesses (S3): the manuscripts and early printings its text survives in, each
  with the siglum an apparatus cites it by. Spec:
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

  Witnesses show on the play's pages, so the table moves `plays.content_version` like
  every other (migration 20261005120000).
  """
  use Ecto.Migration

  def change do
    create table(:play_witnesses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :siglum, :text
      add :title, :text
      add :normalized_title, :text
      add :attribution, :text
      add :pub_place, :text
      add :publisher, :text
      add :date, :text
      add :format, :text
      add :witness_type, :string
      add :shelfmark, :text
      add :note, :text
      add :position, :integer, null: false, default: 0
      add :origin, :string, null: false, default: "manual"
      add :filemaker_id, :text

      timestamps(type: :utc_datetime)
    end

    create index(:play_witnesses, [:play_id, :position])
    create unique_index(:play_witnesses, [:play_id, :siglum])

    execute "CREATE TRIGGER play_witnesses_touch_play AFTER INSERT OR UPDATE OR DELETE ON play_witnesses FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
            "DROP TRIGGER play_witnesses_touch_play ON play_witnesses"
  end
end
```

Create `lib/playcode/witnesses/witness.ex`:

```elixir
defmodule Playcode.Witnesses.Witness do
  @moduledoc """
  One witness of a play's text: a manuscript or early printing, with the siglum an
  apparatus cites it by. `origin` works as for `Playcode.Catalogue.PlayEditor`;
  `filemaker_id` is set only by the import, on the struct, and `position` only by
  `Playcode.Witnesses`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # The leaf of FileMaker's T03.1 tree; its "no consta" collapses into the parent.
  @types ~w(manuscript autograph copy early_edition collection collection_single_author
            collection_several_authors loose)

  @fields ~w(play_id siglum title normalized_title attribution pub_place publisher date
             format witness_type shelfmark note origin)a

  schema "play_witnesses" do
    field :siglum, :string
    field :title, :string
    field :normalized_title, :string
    field :attribution, :string
    field :pub_place, :string
    field :publisher, :string
    field :date, :string
    field :format, :string
    field :witness_type, :string
    field :shelfmark, :string
    field :note, :string
    field :position, :integer, default: 0
    field :origin, :string, default: "manual"
    field :filemaker_id, :string

    belongs_to :play, Playcode.Catalogue.Play

    timestamps(type: :utc_datetime)
  end

  def types, do: @types

  @doc "What a form and the imports may set."
  def changeset(witness, attrs) do
    witness
    |> cast(attrs, @fields)
    |> validate_required([:play_id])
    |> validate_inclusion(:witness_type, @types)
    |> validate_inclusion(:origin, Playcode.Catalogue.origins())
    |> validate_described()
    |> unique_constraint([:play_id, :siglum],
      error_key: :siglum,
      message: "is already used by another witness of this play"
    )
  end

  defp validate_described(changeset) do
    if Enum.any?([:title, :normalized_title, :note], &get_field(changeset, &1)),
      do: changeset,
      else: add_error(changeset, :title, "needs a title, a normalised title or a note")
  end
end
```

Create `lib/playcode/witnesses.ex`:

```elixir
defmodule Playcode.Witnesses do
  @moduledoc """
  A play's witnesses (S3): the manuscripts and early printings its text survives in.
  Spec: docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.
  """

  import Ecto.Query
  import Ecto.Changeset, only: [change: 2, get_field: 2, put_change: 3]

  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.Repo
  alias Playcode.Witnesses.Witness

  @doc "The play's witnesses, in order."
  def list_for_play(play_id) do
    Witness
    |> where([w], w.play_id == ^play_id)
    |> order_by([w], asc: w.position, asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  The play's witness `id`, or nil. Scoped to the play because the id arrives from the
  browser: another play's witness, a deleted one or a malformed id is nil.
  """
  def get_witness(play_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Witness, id: id, play_id: play_id)
      :error -> nil
    end
  end

  def change_witness(%Witness{} = witness, attrs \\ %{}), do: Witness.changeset(witness, attrs)

  @doc """
  Adds a witness after the play's last. `attrs` carry its `play_id`; `base` is the struct
  to start from, so the FileMaker import can set `filemaker_id`.
  """
  def create_witness(attrs, %Witness{} = base \\ %Witness{}) do
    changeset = Witness.changeset(base, attrs)

    changeset
    |> put_change(:position, next_position(get_field(changeset, :play_id)))
    |> Repo.insert()
  end

  def update_witness(%Witness{} = witness, attrs),
    do: witness |> Witness.changeset(attrs) |> Repo.update()

  def delete_witness(%Witness{} = witness), do: Repo.delete(witness)

  @doc "Swaps a witness with its neighbour and renumbers the play's. A move past either end is a no-op."
  def move_witness(%Witness{} = witness, direction) when direction in [:up, :down] do
    witnesses = list_for_play(witness.play_id)
    index = Enum.find_index(witnesses, &(&1.id == witness.id))
    target = if direction == :up, do: index && index - 1, else: index && index + 1

    if is_nil(index) or target < 0 or target >= length(witnesses) do
      :ok
    else
      {:ok, :ok} =
        Repo.transaction(fn ->
          witnesses
          |> List.replace_at(index, Enum.at(witnesses, target))
          |> List.replace_at(target, Enum.at(witnesses, index))
          |> Enum.with_index()
          |> Enum.each(fn {w, i} -> if w.position != i, do: Repo.update!(change(w, position: i)) end)
        end)

      :ok
    end
  end

  @doc """
  The sigla a TEI import must not bring in for the play: its witnesses' (the file's own
  are removed before a re-import reads them) and its modern editions', which live in the
  bibliography.
  """
  def taken_sigla(play_id) do
    witnesses =
      from(w in Witness, where: w.play_id == ^play_id and not is_nil(w.siglum), select: w.siglum)

    editions =
      from(l in Link,
        join: e in Entry,
        on: e.id == l.entry_id,
        where: l.play_id == ^play_id and not is_nil(e.siglum),
        select: e.siglum
      )

    MapSet.new(Repo.all(witnesses) ++ Repo.all(editions))
  end

  # max + 1, not a count: a deletion leaves a gap, and a count would tie the next witness
  # with the one after the gap.
  defp next_position(nil), do: 0

  defp next_position(play_id) do
    case Repo.aggregate(from(w in Witness, where: w.play_id == ^play_id), :max, :position) do
      nil -> 0
      max -> max + 1
    end
  end
end
```

Note `Repo.transaction/1` returns `{:ok, value}` where `value` is the function's result; `Enum.each/2` returns `:ok`, hence `{:ok, :ok}`.

In `lib/playcode/catalogue/play.ex`, after `has_many :play_places, Playcode.Places.PlayPlace` add:

```elixir
    has_many :witnesses, Playcode.Witnesses.Witness
```

In `lib/playcode/catalogue.ex`, add `alias Playcode.Witnesses.Witness` with the other aliases at the top, and in `with_all/2` after the `sources:` line add:

```elixir
      witnesses: from(w in Witness, order_by: [asc: w.position, asc: w.inserted_at]),
```

In `lib/playcode/activity_log/entry.ex`, append `play_witness` to `@resource_types`:

```elixir
  @resource_types ~w(play character division element note editor source editorial_note user place play_place bibliography_entry play_bibliography play_witness)
```

Append to `priv/gettext/errors.pot`:

```
msgid "needs a title, a normalised title or a note"
msgstr ""

msgid "is already used by another witness of this play"
msgstr ""
```

Append to `priv/gettext/es/LC_MESSAGES/errors.po`:

```
msgid "needs a title, a normalised title or a note"
msgstr "necesita un título, un título normalizado o una observación"

msgid "is already used by another witness of this play"
msgstr "ya lo usa otro testimonio de esta obra"
```

Migrate dev too: `mix ecto.migrate`.

- [ ] **Step 4: Run them and watch them pass**

Run: `mix test test/playcode/witnesses_test.exs test/playcode/content_version_test.exs test/playcode_web/error_translations_test.exs`
Expected: all pass. Prove the trigger test bites, then put everything back:

```bash
MIX_ENV=test mix ecto.rollback          # drops play_witnesses from the test database
# comment out the `execute "CREATE TRIGGER play_witnesses_touch_play …"` line
mix test test/playcode/content_version_test.exs   # migrates without the trigger: expect 2 failures,
                                                  # "every table with a play_id has the content trigger"
                                                  # and "witness did not move the play's version"
MIX_ENV=test mix ecto.rollback
# restore the line
mix test test/playcode/content_version_test.exs   # migrates with it: all pass
```

- [ ] **Step 5: Refactor while green** — compare `move_witness/2` with `Places.move_play_place/2`: this one renumbers in the same pass, so it needs no `renumber/1`. Check `create_witness/2` is the only place `position` is set. Re-run Step 4's command.

- [ ] **Step 6: Format, full suite, commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
git add priv/repo/migrations/20261010120000_create_play_witnesses.exs lib/playcode/witnesses.ex lib/playcode/witnesses/witness.ex lib/playcode/catalogue/play.ex lib/playcode/catalogue.ex lib/playcode/activity_log/entry.ex priv/gettext/errors.pot priv/gettext/es/LC_MESSAGES/errors.po test/playcode/witnesses_test.exs test/playcode/content_version_test.exs
git commit -m "feat(witnesses): a play's witnesses, in order, each siglum the play's own

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The printed line and the TEI helpers

**Files:**
- Modify: `lib/playcode/witnesses.ex`
- Test: `test/playcode/witnesses_test.exs`

**Interfaces:**
- Consumes: `Playcode.Witnesses.Witness`, `Playcode.PlayContent.InlineMarkup.parts/1` (returns `%{text: binary, italic: boolean, stage: nil | map}` parts)
- Produces:
  - `Witnesses.parts(witness) :: [%{text: String.t(), italic: boolean}]`
  - `Witnesses.plain(witness) :: String.t()`
  - `Witnesses.html(witness) :: {:safe, iodata}`
  - `Witnesses.xml_id(%{siglum: String.t() | nil}) :: String.t() | nil`
  - `Witnesses.tei_type(type) :: {String.t(), String.t() | nil} | nil`
  - `Witnesses.type_from_tei(type, subtype) :: String.t() | nil`

- [ ] **Step 1: Write the failing tests** — append to `test/playcode/witnesses_test.exs`, before the final `end`:

```elixir
  describe "the printed line" do
    alias Playcode.Witnesses.Witness

    test "every field, in emothe.uv.es's order" do
      witness = %Witness{
        title: "THE Tragicall Historie of HAMLET Prince of Denmarke.",
        normalized_title: "The Tragical History of Hamlet, Prince of Denmark",
        attribution: "Shakespeare, William",
        pub_place: "London",
        publisher: "Ling, Nicholas; Trundell, John",
        date: "1603",
        format: "4º",
        note: "Printer: Simmes, Valentine",
        shelfmark: "C.34.k.1"
      }

      assert Witnesses.plain(witness) ==
               "THE Tragicall Historie of HAMLET Prince of Denmarke. " <>
                 "[The Tragical History of Hamlet, Prince of Denmark]. Shakespeare, William. " <>
                 "London. Ling, Nicholas; Trundell, John. 1603. 4º. " <>
                 "Printer: Simmes, Valentine. Archivo: C.34.k.1."
    end

    test "an empty field drops out with its full stop, and one ending in a stop gets no second" do
      assert Witnesses.plain(%Witness{title: "El conde de Sex", shelfmark: "16722"}) ==
               "El conde de Sex. Archivo: 16722."

      assert Witnesses.plain(%Witness{
               normalized_title: "Ralph Roister Doister",
               date: "1566 ?",
               note: "[1566 ?] No title page."
             }) == "[Ralph Roister Doister]. 1566 ? [1566 ?] No title page."
    end

    test "line breaks and doubled spaces collapse, the whole title is italic, the rest escaped" do
      witness = %Witness{
        title: "Oeuvres <<et>> meslanges,  &\nLimodin\n",
        note: "edición de Charles de la\nMothe\n"
      }

      assert Witnesses.plain(witness) ==
               "Oeuvres et meslanges, & Limodin. edición de Charles de la Mothe."

      assert witness |> Witnesses.html() |> Phoenix.HTML.safe_to_string() ==
               "<em>Oeuvres et meslanges, &amp; Limodin</em>. edición de Charles de la Mothe."
    end
  end

  describe "in TEI" do
    alias Playcode.Witnesses.Witness

    test "the xml:id is the siglum when XML allows it, prefixed and cleaned when not" do
      for {siglum, id} <- [
            {"Q1", "Q1"},
            {"Aut.", "Aut."},
            {"PXXIV", "PXXIV"},
            {"1623b", "wit-1623b"},
            {"Q 1", "wit-Q_1"},
            {nil, nil}
          ] do
        assert Witnesses.xml_id(%Witness{siglum: siglum}) == id, inspect(siglum)
      end
    end

    test "every type has its TEI pair, and the pair names the type back" do
      for type <- Witness.types() do
        {tei_type, subtype} = Witnesses.tei_type(type)
        assert Witnesses.type_from_tei(tei_type, subtype) == type
      end

      assert Witnesses.tei_type(nil) == nil
      assert Witnesses.type_from_tei("libro", nil) == nil
    end
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/witnesses_test.exs`
Expected: 5 failures, `function Playcode.Witnesses.plain/1 is undefined` (and `html/1`, `xml_id/1`, `tei_type/1`).

- [ ] **Step 3: Write the smallest implementation** — in `lib/playcode/witnesses.ex`, add `alias Playcode.PlayContent.InlineMarkup` to the aliases, extend the moduledoc with:

```
  The printed line (`parts/1`, `plain/1`, `html/1`) is emothe.uv.es's, and the admin
  preview, `/plays/:code` and the static site all print through it. `xml_id/1` and
  `tei_type/1` are the TEI export's and import's, so the `<app>` work can point `wit` at
  the same id.
```

and add, before the private `next_position` helpers:

```elixir
  # FileMaker's T03.1 leaves as TEI's {bibl@type, bibl@subtype}, in its own Spanish terms,
  # as S4's biblStruct types are.
  @tei_types %{
    "manuscript" => {"manuscrito", nil},
    "autograph" => {"manuscrito", "autografo"},
    "copy" => {"manuscrito", "copia"},
    "early_edition" => {"edicion_antigua", nil},
    "collection" => {"edicion_antigua", "coleccion"},
    "collection_single_author" => {"edicion_antigua", "coleccion_de_autor"},
    "collection_several_authors" => {"edicion_antigua", "coleccion_de_diversos_autores"},
    "loose" => {"edicion_antigua", "suelta"}
  }

  @doc """
  The witness as `%{text: binary, italic: boolean}` segments, emothe.uv.es's line:
  `<<Title>>. [Normalised title]. Attribution. City. Publisher. Date. Format. Note.
  Archivo: Shelfmark.` An empty field drops out with its full stop, a value ending in `.`,
  `?` or `!` gets no second one, and whitespace is collapsed. `Archivo:` is FileMaker's
  label and is not translated.
  """
  def parts(%Witness{} = w) do
    [
      wrap(w.title && String.replace(w.title, ["<<", ">>"], ""), "<<", ">>"),
      wrap(w.normalized_title, "[", "]"),
      clean(w.attribution),
      clean(w.pub_place),
      clean(w.publisher),
      clean(w.date),
      clean(w.format),
      clean(w.note),
      wrap(w.shelfmark, "Archivo: ", "")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(" ", &stop/1)
    |> InlineMarkup.parts()
  end

  @doc "The witness as plain text."
  def plain(%Witness{} = w), do: w |> parts() |> Enum.map_join(& &1.text)

  @doc "The witness as safe HTML: `<em>` for the italics, the rest escaped."
  def html(%Witness{} = w) do
    {:safe,
     w
     |> parts()
     |> Enum.map(fn
       %{text: text, italic: true} -> ["<em>", escape(text), "</em>"]
       %{text: text} -> escape(text)
     end)}
  end

  @doc "A witness type as TEI's `{bibl@type, bibl@subtype}`; nil for none."
  def tei_type(type), do: @tei_types[type]

  @doc "The witness type a `<bibl type subtype>` names, or nil."
  def type_from_tei(type, subtype) do
    Enum.find_value(@tei_types, fn {key, pair} -> if pair == {type, subtype}, do: key end)
  end

  @doc """
  The witness's `xml:id`: its siglum when that is an XML name, else `wit-` and the siglum
  with anything a name cannot hold made `_` (EMOTHE0530's `1623b`). Nil without a siglum.
  The siglum itself always travels verbatim as `@n`.
  """
  def xml_id(%{siglum: nil}), do: nil

  def xml_id(%{siglum: siglum}) do
    # ponytail: letters, digits, `.`, `-`, `_`; XML's NameChar allows a few more
    # (combining marks, `·`), which no siglum in the corpus uses.
    if siglum =~ ~r/\A[\p{L}_][\p{L}\p{N}._-]*\z/u,
      do: siglum,
      else: "wit-" <> String.replace(siglum, ~r/[^\p{L}\p{N}._-]/u, "_")
  end

  defp wrap(value, open, close) do
    case clean(value) do
      nil -> nil
      text -> open <> text <> close
    end
  end

  defp clean(nil), do: nil

  defp clean(text) do
    case text |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  # "Denmarke.>>" ends its sentence inside the italics, so the stop is looked for before them.
  defp stop(text) do
    if text |> String.trim_trailing(">>") |> String.ends_with?([".", "?", "!"]),
      do: text,
      else: text <> "."
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
```

- [ ] **Step 4: Run them and watch them pass**

Run: `mix test test/playcode/witnesses_test.exs`
Expected: all pass.

- [ ] **Step 5: Refactor while green** — compare `html/1` with `Bibliography.Citation.html/2`: the same two segment shapes and no URL segment; keep them apart rather than couple the two renderers. Re-run Step 4.

- [ ] **Step 6: Format, full suite, commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
git add lib/playcode/witnesses.ex test/playcode/witnesses_test.exs
git commit -m "feat(witnesses): emothe.uv.es's printed line, and the TEI id and type of a witness

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: TEI `listWit`, both ways

**Files:**
- Modify: `lib/playcode/export/tei_xml.ex` (`generate/2` preloads near line 30; `build_source_desc/1` near line 270)
- Modify: `lib/playcode/import/tei_parser.ex` (aliases near line 13; `mixed_ownership_total/1` line 133; `replaced_counts/1` and `preserved_counts/1` near lines 137-160; `reset_tei_content/1` near line 265; `import_header/1` near line 324; a new section after `import_sources/2`, near line 772)
- Modify: `lib/playcode/export/static_site/fingerprint.ex` (`@modules`, line 26)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/import/tei_preview_test.exs`, `test/playcode/export/tei_validator_test.exs`

**Interfaces:**
- Consumes: `Witnesses.create_witness/1`, `taken_sigla/1`, `xml_id/1`, `tei_type/1`, `type_from_tei/2`; `Play.witnesses`
- Produces: `TeiParser.preview_import/1`'s `replaces` and `preserves` gain `:witnesses`; `mixed_ownership_total/1` sums it.

- [ ] **Step 1: Write the failing tests** — in `test/playcode/tei_roundtrip_test.exs` add `import Playcode.TestFixtures, only: [bibliography_fixture: 2]` under `import Playcode.ImportHelpers`, and add before the final top-level `test "exporting, re-importing and exporting again changes nothing"`:

```elixir
  describe "witnesses" do
    @list_wit """
    <listWit>
      <witness xml:id="Q1" n="Q1">
        <bibl type="edicion_antigua" subtype="suelta">
          <title>THE Tragicall Historie of HAMLET</title>
          <title type="normalized">The Tragical History of Hamlet</title>
          <author>Shakespeare, William</author>
          <pubPlace>London</pubPlace>
          <publisher>Ling, Nicholas</publisher>
          <date when="1603">1603</date>
          <extent>4º</extent>
          <idno type="shelfmark">C.34.k.1</idno>
          <note>Usual abbreviation: Q1.</note>
        </bibl>
      </witness>
      <listWit>
        <witness xml:id="wit-1623b" n="1623b">
          <bibl type="edicion_antigua" subtype="coleccion"><title>Œuvres</title></bibl>
        </witness>
      </listWit>
      <witness><bibl type="manuscrito" subtype="autografo"><title>El bastardo Mudarra</title></bibl></witness>
    </listWit>
    """

    test "every field of a witness comes back, in order, with no empty paragraph before them" do
      xml = roundtrip(tei(source_desc: @list_wit))

      assert [
               {%{"n" => "Q1", "xml:id" => "Q1"}, _},
               {%{"n" => "1623b", "xml:id" => "wit-1623b"}, _},
               {unnamed, _}
             ] = xml_elements(xml, "witness")

      refute Map.has_key?(unnamed, "xml:id")
      assert xml_texts(xml, "p", within: "sourceDesc") == []

      assert xml_elements(xml, "title", within: "witness") == [
               {%{}, "THE Tragicall Historie of HAMLET"},
               {%{"type" => "normalized"}, "The Tragical History of Hamlet"},
               {%{}, "Œuvres"},
               {%{}, "El bastardo Mudarra"}
             ]

      for {tag, text} <- [
            {"author", "Shakespeare, William"},
            {"pubPlace", "London"},
            {"publisher", "Ling, Nicholas"},
            {"extent", "4º"},
            {"note", "Usual abbreviation: Q1."}
          ] do
        assert xml_texts(xml, tag, within: "witness") == [text], tag
      end

      assert xml_elements(xml, "date", within: "witness") == [{%{"when" => "1603"}, "1603"}]
      assert xml_elements(xml, "idno", within: "witness") == [{%{"type" => "shelfmark"}, "C.34.k.1"}]

      assert for({attrs, _} <- xml_elements(xml, "bibl", within: "witness"),
                 do: {attrs["type"], attrs["subtype"]}) == [
               {"edicion_antigua", "suelta"},
               {"edicion_antigua", "coleccion"},
               {"manuscrito", "autografo"}
             ]
    end

    test "a witness described in plain words keeps its words, as its note" do
      words = "anon. [no title page]. London: printed by Richard Pynson, [1518-19?]. STC 10604."

      xml =
        roundtrip(tei(source_desc: ~s(<listWit><witness xml:id="Q1"><bibl>#{words}</bibl></witness></listWit>)))

      assert xml_elements(xml, "witness") == [{%{"n" => "Q1", "xml:id" => "Q1"}, words}]
      assert xml_texts(xml, "note", within: "witness") == [words]
    end

    test "a siglum repeated in the file comes in once" do
      xml =
        roundtrip(
          tei(
            source_desc:
              ~s(<listWit><witness xml:id="Q1"><bibl>Uno</bibl></witness>) <>
                ~s(<witness n="Q1"><bibl>Otro</bibl></witness></listWit>)
          )
        )

      assert xml_elements(xml, "witness") == [{%{"n" => "Q1", "xml:id" => "Q1"}, "Uno"}]
    end

    # EMOTHE0460's listWit lists its early quartos and the modern editions its apparatus
    # cites; the editions live in the bibliography, with their siglum.
    test "a re-import keeps hand-typed witnesses and skips a siglum one of them or an edition holds" do
      code = "WIT#{System.unique_integer([:positive])}"
      play = import_tei!(tei(code: code))

      bibliography_fixture(play, %{
        "kind" => "modern_edition",
        "monogr_title" => "Chief Pre-Shakespearean Dramas",
        "siglum" => "ADA"
      })

      {:ok, _} =
        Playcode.Witnesses.create_witness(%{"play_id" => play.id, "siglum" => "Q2", "title" => "Typed by hand"})

      file =
        tei(
          code: code,
          source_desc: """
          <listWit>
            <witness xml:id="ADA"><bibl>Adams, Joseph Quincy, ed. Chief Pre-Shakespearean Dramas. 1924.</bibl></witness>
            <witness xml:id="Q1"><bibl>anon. London: Pynson, [1518-19?].</bibl></witness>
            <witness xml:id="Q2"><bibl>anon. London: Pynson, [1526-28?].</bibl></witness>
          </listWit>
          """
        )

      expected = [{"Q2", "Typed by hand"}, {"Q1", "anon. London: Pynson, [1518-19?]."}]
      listed = fn xml -> for {%{"n" => n}, text} <- xml_elements(xml, "witness"), do: {n, text} end

      assert listed.(roundtrip(file)) == expected
      assert listed.(roundtrip(file)) == expected
    end

    test "exporting, re-importing and exporting again changes nothing" do
      first = tei(code: "WIT1", source_desc: "<bibl><title>Base</title></bibl>" <> @list_wit) |> roundtrip()
      second = first |> String.replace("WIT1", "WIT2") |> roundtrip()

      assert String.replace(second, "WIT2", "WIT1") == first
    end
  end
```

In `test/playcode/import/tei_preview_test.exs`, add `witnesses: 0` to both exact maps of "an unknown code previews as a new play", with a comment above the first assertion:

```elixir
    # Witnesses (S3) are a fifth table of mixed ownership, so the preview counts them too.
    assert preview.replaces == %{
             divisions: 0,
             elements: 0,
             characters: 0,
             editors: 0,
             sources: 0,
             notes: 0,
             places: 0,
             witnesses: 0
           }

    assert preview.preserves == %{editors: 0, sources: 0, notes: 0, places: 0, witnesses: 0}
```

In `test/playcode/export/tei_validator_test.exs`, add after the stage-direction test:

```elixir
    # Every witness type, a siglum that is no XML name, a witness with no siglum, and no
    # sources: the sourceDesc then holds the listWit alone. Under a code of its own, for the
    # same reason as the bibliography test.
    test "witnesses of every type export as schema-valid TEI" do
      play =
        @fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0759_AutoDeLaBarcaDelInfierno</title>),
          ~s(<title key="archivo">WIT#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

      for source <- play.sources, do: {:ok, _} = Catalogue.delete_play_source(source)

      for {type, i} <- Enum.with_index(Playcode.Witnesses.Witness.types()) do
        {:ok, _} =
          Playcode.Witnesses.create_witness(%{
            "play_id" => play.id,
            "siglum" => "S#{i}",
            "title" => "Título",
            "normalized_title" => "Título normalizado",
            "attribution" => "Autor, Ana",
            "pub_place" => "Madrid",
            "publisher" => "Imprenta",
            "date" => "1603",
            "format" => "4º",
            "witness_type" => type,
            "shelfmark" => "BN 16630",
            "note" => "Nota"
          })
      end

      {:ok, _} =
        Playcode.Witnesses.create_witness(%{"play_id" => play.id, "siglum" => "1623b", "title" => "Œuvres", "date" => "s. a."})

      {:ok, _} = Playcode.Witnesses.create_witness(%{"play_id" => play.id, "note" => "Sin sigla"})

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ "<listWit>"
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs test/playcode/import/tei_preview_test.exs`
Expected: the witness tests fail (`xml_elements(xml, "witness")` is `[]`), the preview tests fail on the missing `witnesses:` key.

- [ ] **Step 3: Write the smallest implementation — export.** In `lib/playcode/export/tei_xml.ex`, add `alias Playcode.Witnesses`, add `:witnesses` to the `Repo.preload` list in `generate/2`, and replace the whole of `defp build_source_desc(play) do … end` with:

```elixir
  defp build_source_desc(play) do
    bibls =
      Enum.map(play.sources, fn source ->
        children =
          [
            if(source.title, do: element(:title, source.title)),
            if(source.author, do: element(:author, source.author)),
            if source.editor do
              attrs = if source.editor_role, do: %{role: source.editor_role}, else: %{}
              element(:editor, attrs, source.editor)
            end,
            if(source.publisher, do: element(:publisher, source.publisher)),
            if(source.pub_place, do: element(:pubPlace, source.pub_place)),
            if(source.pub_date, do: element(:date, source.pub_date)),
            if(source.language, do: element(:lang, source.language)),
            if(source.note, do: element(:note, source.note))
          ]
          |> Enum.reject(&is_nil/1)

        element(:bibl, children)
      end)

    # The schema takes paragraphs, or bibls and lists, never both: the empty <p/> stands in
    # only when there is nothing else.
    children = Enum.reject(bibls ++ [build_list_wit(play)], &is_nil/1)
    element(:sourceDesc, if(children == [], do: [element(:p, "")], else: children))
  end

  # The play's witnesses (S3). @n is the siglum verbatim and @xml:id what an apparatus
  # points at (Witnesses.xml_id/1). The modern editions a reading may also cite stay in
  # <back>, with their siglum.
  defp build_list_wit(%{witnesses: []}), do: nil

  defp build_list_wit(play) do
    element(:listWit, play.witnesses |> Enum.sort_by(& &1.position) |> Enum.map(&build_witness/1))
  end

  defp build_witness(w) do
    attrs = Map.reject(%{"n" => w.siglum, "xml:id" => Witnesses.xml_id(w)}, &is_nil(elem(&1, 1)))
    {type, subtype} = Witnesses.tei_type(w.witness_type) || {nil, nil}
    bibl_attrs = Map.reject(%{type: type, subtype: subtype}, &is_nil(elem(&1, 1)))
    date = if filled?(w.date), do: String.trim(w.date)

    children =
      Enum.reject(
        [
          if(filled?(w.title), do: element(:title, build_inline_content(w.title))),
          if(filled?(w.normalized_title),
            do: element(:title, %{type: "normalized"}, build_inline_content(w.normalized_title))
          ),
          if(filled?(w.attribution), do: element(:author, w.attribution)),
          if(filled?(w.pub_place), do: element(:pubPlace, w.pub_place)),
          if(filled?(w.publisher), do: element(:publisher, w.publisher)),
          if(date,
            do: element(:date, if(date =~ ~r/^\d{4}$/, do: %{when: date}, else: %{}), date)
          ),
          if(filled?(w.format), do: element(:extent, w.format)),
          if(filled?(w.shelfmark), do: element(:idno, %{type: "shelfmark"}, w.shelfmark)),
          if(filled?(w.note), do: element(:note, build_inline_content(w.note)))
        ],
        &is_nil/1
      )

    element(:witness, attrs, [element(:bibl, bibl_attrs, children)])
  end
```

The sources half is today's code unchanged; only the last two lines of the function and the two new functions are new.

- [ ] **Step 4: Write the smallest implementation — import.** In `lib/playcode/import/tei_parser.ex`:

Aliases: add `alias Playcode.Witnesses` and `alias Playcode.Witnesses.Witness`.

`mixed_ownership_total/1`: `[:editors, :sources, :notes, :places, :witnesses]`, and in its doc replace "Those four tables — editors, sources, notes and places —" with "Those five tables — editors, sources, notes, places and witnesses —".

`replaced_counts(nil)` gains `witnesses: 0`; `replaced_counts(%Play{id: id})` gains `witnesses: count_rows(Witness, id, "tei")`; `preserved_counts(nil)` gains `witnesses: 0`; `preserved_counts(%Play{id: id})` gains `witnesses: count_rows(Witness, id) - count_rows(Witness, id, "tei")`.

`reset_tei_content/1`: `for schema <- [PlayEditor, PlaySource, PlayEditorialNote, Witness] do`.

`import_header/1`: after `import_sources(file_desc, play)` add `import_witnesses(file_desc, play)`.

After `import_sources/2`, add:

```elixir
  # --- Witnesses ---

  # `sourceDesc/listWit`, nested lists read in order (S3). A siglum the play already has —
  # a witness typed by hand, a modern edition in its bibliography, or one earlier in the
  # same file — is left out (Witnesses.taken_sigla/1, after reset_tei_content/1 removed the
  # file's own). A witness with nothing to print fails its changeset and is left out too.
  defp import_witnesses(file_desc, play) do
    with {_, _, desc_children} <- find_child(elem(file_desc, 2), "sourceDesc"),
         {_, _, _} = list_wit <- find_child(desc_children, "listWit") do
      list_wit
      |> witness_elements()
      |> Enum.reduce(Witnesses.taken_sigla(play.id), fn witness, taken ->
        attrs = witness |> witness_attrs() |> Map.merge(%{play_id: play.id, origin: "tei"})

        if attrs.siglum in taken do
          taken
        else
          _ = Witnesses.create_witness(attrs)
          if attrs.siglum, do: MapSet.put(taken, attrs.siglum), else: taken
        end
      end)
    end

    :ok
  end

  defp witness_elements({_name, _attrs, children}) do
    Enum.flat_map(children, fn
      {"witness", _, _} = witness -> [witness]
      {"listWit", _, _} = nested -> witness_elements(nested)
      _other -> []
    end)
  end

  # A <bibl> written field by field, as the export writes one, maps back to its columns.
  # Plain words (EMOTHE0460's "anon. [no title page]. London: printed by Richard Pynson…")
  # are kept whole as the note rather than guessed into fields.
  defp witness_attrs({"witness", attrs, children}) do
    {bibl_attrs, parts} =
      case find_child(children, "bibl") do
        {_, bibl_attrs, bibl_children} -> {bibl_attrs, bibl_children}
        nil -> {[], children}
      end

    base = %{
      siglum: attr_value(attrs, "n") || attr_value(attrs, "xml:id"),
      witness_type:
        Witnesses.type_from_tei(attr_value(bibl_attrs, "type"), attr_value(bibl_attrs, "subtype"))
    }

    if Enum.any?(parts, &match?({name, _, _} when name in ~w(title author pubPlace publisher date extent idno), &1)) do
      Map.merge(base, %{
        title: parts |> typed("title", nil) |> safe_text(),
        normalized_title: parts |> typed("title", "normalized") |> safe_text(),
        attribution: safe_text(find_child(parts, "author")),
        pub_place: safe_text(find_child(parts, "pubPlace")),
        publisher: safe_text(find_child(parts, "publisher")),
        date: safe_text(find_child(parts, "date")),
        format: safe_text(find_child(parts, "extent")),
        shelfmark: parts |> typed("idno", "shelfmark") |> safe_text(),
        note: safe_text(find_child(parts, "note"))
      })
    else
      Map.put(base, :note, text_content({"bibl", [], parts}))
    end
  end

  # The first `name` child whose @type is `type` (nil: no @type).
  defp typed(children, name, type),
    do: children |> find_children(name) |> Enum.find(&(attr_value(elem(&1, 1), "type") == type))
```

- [ ] **Step 5: Write the smallest implementation — fingerprint.** `TeiXml` is fingerprinted and now calls `Playcode.Witnesses`, which decides what the `.xml` file says. In `lib/playcode/export/static_site/fingerprint.ex`, add `Playcode.Witnesses,` to `@modules` after `Playcode.Places.PlayPlace,`.

- [ ] **Step 6: Run them and watch them pass**

Run: `mix test test/playcode/tei_roundtrip_test.exs test/playcode/import test/playcode/export/static_site/fingerprint_test.exs`
Expected: all pass. Prove the fingerprint line bites: remove it, run `mix test test/playcode/export/static_site/fingerprint_test.exs`, expect "every module the export calls is in the fingerprint" to fail naming `Playcode.Witnesses`; put it back.

Then the schema check (needs `xmllint`, about 15 s a test):
Run: `mix test test/playcode/export/tei_validator_test.exs --include slow`
Expected: all pass. Prove the `<p/>` rule bites: temporarily write `bibls ++ [element(:p, ""), build_list_wit(play)]`, expect the witness validation to fail, restore.

- [ ] **Step 7: Refactor while green** — `witness_attrs/1` and `import_sources/2` both read `<bibl>` children with `safe_text(find_child(…))`; leave them separate (different columns). Check `typed/3` is not already in the parser under another name (`grep -n "attr_value(elem(&1, 1), \"type\")" lib/playcode/import/tei_parser.ex`); reuse an existing helper if there is one. Re-run Step 6's first command.

- [ ] **Step 8: Format, full suite, commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
git add lib/playcode/export/tei_xml.ex lib/playcode/import/tei_parser.ex lib/playcode/export/static_site/fingerprint.ex test/playcode/tei_roundtrip_test.exs test/playcode/import/tei_preview_test.exs test/playcode/export/tei_validator_test.exs
git commit -m "feat(tei): witnesses in sourceDesc/listWit, written and read back

A siglum that is no XML name keeps @n and gets a prefixed xml:id; a siglum
the play already has (by hand, or a modern edition's) is skipped on import.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The FileMaker import

**Files:**
- Create: `test/fixtures/filemaker/witnesses/regenerate.exs`, then run it to write `test/fixtures/filemaker/witnesses/T03_ObraTestimonio.xml` and `T03.2_Atribucion.xml`
- Create: `lib/playcode/import/witnesses.ex`
- Create: `lib/mix/tasks/playcode.import.witnesses.ex`
- Modify: `lib/playcode/release.ex` (after `import_bibliography/2`)
- Test: `test/playcode/import/witnesses_test.exs` (create), `test/playcode/witnesses/oracle_test.exs` (create), `test/mix/tasks_test.exs`

**Interfaces:**
- Consumes: `Witnesses.create_witness/2`, `Witnesses.plain/1`, `Witness`; `FilemakerXml.read/1`; `FilemakerSync.base_code/1`, `all_plays/0`; `ActivityLog.log!/1`
- Produces:
  - `Playcode.Import.Witnesses.load(dir) :: {:ok, %{witnesses: [map], attributions: [map]}} | {:error, {file, reason}}`
  - `attributions(data) :: %{id => name}`
  - `skip_reason(row) :: :test_record | :empty | nil`
  - `witness_attrs(row, attributions) :: map` (atom keys, the witness columns)
  - `plan(data, plays) :: %{witnesses: [map], already_imported: [code], skipped: %{reason => [ref]}, dropped: [ref], not_held: integer}`
  - `apply_plan(plan, opts \\ []) :: {:ok, %{witnesses: integer}}`
  - `report(plan) :: [String.t()]`
  - `Playcode.Release.import_witnesses(dir, opts \\ [])`

- [ ] **Step 1: Write the fixture script** — create `test/fixtures/filemaker/witnesses/regenerate.exs`:

```elixir
# Rebuilds the witness sample in this directory from the git-ignored FileMaker dump: the
# T03 records below and the T03.2 attributions they name. Rows are copied byte for byte, so
# FileMaker's own rendering (w3_ObrTes_Composicion) comes with them. Run from the
# repository root:
#
#     mix run --no-start test/fixtures/filemaker/witnesses/regenerate.exs
#
# One record per rule: every type, Jodelle's name dropped from a Spanish play (77, 79) and
# kept on his own (92), sigla that are no XML name (142, 143), no title (140), the test
# record (32), an empty one (15), a version no play holds (95). See "Testing" in
# docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

alias Playcode.Import.FilemakerXml

dump = "doc/ctce_dades"
out = Path.dirname(__ENV__.file)

records = ~w(15 32 33 36 77 79 92 95 140 142 143 240 267 268 269 499)

# Keeps the rows of `file` whose `field` is in `keep`, and rewrites FOUND to match.
keep = fn file, field, keep ->
  xml = File.read!(Path.join(dump, file))

  names =
    ~r/<FIELD [^>]*NAME="([^"]+)"/ |> Regex.scan(xml, capture: :all_but_first) |> List.flatten()

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
    head <>
      ~s(<RESULTSET FOUND="#{length(kept)}">) <> Enum.join(kept) <> "</RESULTSET></FMPXMLRESULT>"
  )
end

keep.("T03_ObraTestimonio.xml", "_kp_IdObraTestimonio", MapSet.new(records))
{:ok, kept} = FilemakerXml.read(Path.join(out, "T03_ObraTestimonio.xml"))
keep.("T03.2_Atribucion.xml", "_kp_IdAtribucion", MapSet.new(kept, & &1["_k_IdAtribucion"]))

IO.puts("wrote the witness sample to #{out}")
```

Run (the files are one line each, so count the rows, not the lines):
```bash
mkdir -p test/fixtures/filemaker/witnesses
mix run --no-start test/fixtures/filemaker/witnesses/regenerate.exs
for f in test/fixtures/filemaker/witnesses/*.xml; do echo "$f $(grep -o '<ROW ' "$f" | wc -l)"; done
```
Expected: `wrote the witness sample to …`, then `T03.2_Atribucion.xml 5` (attributions 13, 14, 36, 51, 105) and `T03_ObraTestimonio.xml 16`.

- [ ] **Step 2: Write the failing tests** — create `test/playcode/import/witnesses_test.exs`:

```elixir
defmodule Playcode.Import.WitnessesTest do
  @moduledoc """
  What the witness import would write, from a sample of FileMaker's T03 with one record per
  rule (test/fixtures/filemaker/witnesses/regenerate.exs). The writing itself is tested
  through the mix task, in test/mix/tasks_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Import.Witnesses, as: Import
  alias Playcode.Witnesses

  @dump "test/fixtures/filemaker/witnesses"

  setup do
    plays =
      for {code, author} <- [
            {"EMOTHE0010_Hamlet", "William Shakespeare"},
            {"EMOTHE0020_Empty", "Author"},
            {"EMOTHE0153_RomeoAndJuliet", "William Shakespeare"},
            {"EMOTHE0163_Orbecca", "Giovan Battista Giraldi Cinthio"},
            {"EMOTHE0231_Sofonisba", "Giovan Giorgio Trissino"},
            {"EMOTHE0389_ElCondeDeSex", "Antonio Coello"},
            {"EMOTHE0435_ElBastardoMudarra", "Félix Lope de Vega y Carpio"},
            {"EMOTHE0479_Cleopatre", "Étienne Jodelle"},
            {"EMOTHE0530_Pyrame", "Théophile de Viau"}
          ],
          into: %{},
          do: {code, play_fixture(%{"code" => code, "author_name" => author})}

    {:ok, data} = Import.load(@dump)
    %{plays: plays, data: data}
  end

  defp plan(%{plays: plays, data: data}), do: Import.plan(data, Map.values(plays))
  defp on(plan, code), do: for(w <- plan.witnesses, w.code == code, do: w)

  test "a test record and an empty one are skipped by id, whatever play they name", ctx do
    plan = plan(ctx)

    assert plan.skipped == %{test_record: ["T03:32"], empty: ["T03:15"]}
    assert plan.not_held == 1
    assert on(plan, "EMOTHE0020_Empty") == []
  end

  test "each field lands in its column, in FileMaker's order", ctx do
    assert [q1, f1] = on(plan(ctx), "EMOTHE0010_Hamlet")

    assert %{
             filemaker_id: "T03:33",
             siglum: "Q1",
             title: "THE Tragicall Historie of HAMLET Prince of Denmarke.",
             normalized_title: "The Tragical History of Hamlet, Prince of Denmark",
             attribution: "Shakespeare, William",
             pub_place: "London",
             publisher: "Ling, Nicholas; Trundell, John",
             date: "1603",
             format: "4º",
             witness_type: "loose",
             shelfmark: nil,
             note: "Usual abbreviation: Q1. Often referred to as “bad quarto”. Printer: Simmes, Valentine"
           } = q1

    assert %{filemaker_id: "T03:36", siglum: "F1"} = f1
    assert [%{shelfmark: "BN 16630"}] = for(w <- on(plan(ctx), "EMOTHE0389_ElCondeDeSex"), w.filemaker_id == "T03:268", do: w)
  end

  test "the type is the deepest level FileMaker set, its 'no consta' the parent", ctx do
    assert Map.new(plan(ctx).witnesses, &{&1.filemaker_id, &1.witness_type}) == %{
             "T03:33" => "loose",
             "T03:36" => "collection_single_author",
             "T03:77" => "collection_single_author",
             "T03:79" => "autograph",
             "T03:92" => "collection_single_author",
             "T03:140" => "loose",
             "T03:142" => "collection",
             "T03:143" => "loose",
             "T03:240" => "early_edition",
             "T03:267" => "collection_several_authors",
             "T03:268" => "manuscript",
             "T03:269" => "copy",
             "T03:499" => "early_edition"
           }
  end

  test "Jodelle's name is dropped from a Spanish play's witnesses and kept on his own", ctx do
    plan = plan(ctx)

    assert plan.dropped == [
             "T03:77 on EMOTHE0435_ElBastardoMudarra",
             "T03:79 on EMOTHE0435_ElBastardoMudarra"
           ]

    assert Enum.map(on(plan, "EMOTHE0435_ElBastardoMudarra"), & &1.attribution) == [nil, nil]
    assert [%{attribution: "Jodelle, Étienne"}] = on(plan, "EMOTHE0479_Cleopatre")
  end

  test "a siglum the play already has is skipped", ctx do
    {:ok, _} =
      Witnesses.create_witness(%{
        play_id: ctx.plays["EMOTHE0010_Hamlet"].id,
        siglum: "F1",
        title: "Typed by hand"
      })

    plan = plan(ctx)

    assert plan.skipped.siglum_taken == ["T03:36 on EMOTHE0010_Hamlet"]
    assert [%{siglum: "Q1"}] = on(plan, "EMOTHE0010_Hamlet")
  end
end
```

Create `test/playcode/witnesses/oracle_test.exs`:

```elixir
defmodule Playcode.Witnesses.OracleTest do
  @moduledoc """
  Every word FileMaker printed for a witness (`w3_ObrTes_Composicion`, emothe.uv.es's
  line) is in ours. Neither order nor punctuation is compared: test/playcode/witnesses_test.exs
  pins those. The sample is committed; the whole dump is git-ignored, so its sweep runs
  only where it is present. The import drops Jodelle's name on some plays; the oracle
  renders every record as FileMaker holds it, so it sees no such drop.
  """
  use ExUnit.Case, async: true

  alias Playcode.Import.Witnesses, as: Import
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness

  # `%{ref => [word]}` for every witness whose printed line lacks a word FileMaker printed.
  defp misses(dir) do
    {:ok, data} = Import.load(dir)
    attributions = Import.attributions(data)

    data.witnesses
    |> Enum.filter(&is_nil(Import.skip_reason(&1)))
    |> Map.new(fn row ->
      ours = Witnesses.plain(struct(Witness, Import.witness_attrs(row, attributions)))
      missing = MapSet.difference(words(row["w3_ObrTes_Composicion"]), words(ours))
      {"T03:" <> row["_kp_IdObraTestimonio"], Enum.sort(missing)}
    end)
    |> Map.reject(fn {_ref, missing} -> missing == [] end)
  end

  defp words(text) do
    ~r/[\p{L}\p{N}]+/u
    |> Regex.scan(text |> String.replace(~r/<[^>]*>/, " ") |> String.downcase())
    |> List.flatten()
    |> MapSet.new()
  end

  test "the committed sample" do
    assert misses("test/fixtures/filemaker/witnesses") == %{}
  end

  @tag :slow
  test "the whole FileMaker dump, where present" do
    if File.dir?("doc/ctce_dades"), do: assert(misses("doc/ctce_dades") == %{})
  end
end
```

In `test/mix/tasks_test.exs`, add `alias Playcode.Witnesses` to the aliases, a helper after `tmp_dir/0`:

```elixir
  defp witness_lines(play), do: play.id |> Witnesses.list_for_play() |> Enum.map(&Witnesses.plain/1)
```

and a describe block after `describe "playcode.import.bibliography"`:

```elixir
  describe "playcode.import.witnesses" do
    @witnesses "test/fixtures/filemaker/witnesses"

    setup do
      %{
        hamlet: play_fixture(%{"code" => "EMOTHE0010_Hamlet"}),
        mudarra:
          play_fixture(%{
            "code" => "EMOTHE0435_ElBastardoMudarra",
            "author_name" => "Félix Lope de Vega y Carpio"
          })
      }
    end

    test "--dry-run prints the plan and writes nothing", %{hamlet: hamlet} do
      out = run("playcode.import.witnesses", ["--path", @witnesses, "--dry-run"])

      assert out =~ "EMOTHE0010_Hamlet  2 witnesses"
      assert out =~ "witnesses: 4 on 2 plays"

      assert out =~
               "attribution dropped: 2  T03:77 on EMOTHE0435_ElBastardoMudarra, " <>
                 "T03:79 on EMOTHE0435_ElBastardoMudarra"

      assert out =~ "skipped, empty: 1  T03:15"
      assert out =~ "skipped, test_record: 1  T03:32"
      assert out =~ "witnesses on versions not held: 10"
      assert out =~ "dry run, nothing written"
      assert witness_lines(hamlet) == []
    end

    test "writes each play's witnesses in FileMaker's order, as emothe.uv.es prints them", %{
      hamlet: hamlet,
      mudarra: mudarra
    } do
      assert run("playcode.import.witnesses", ["--path", @witnesses]) =~ "created 4 witnesses"

      assert witness_lines(hamlet) == [
               "THE Tragicall Historie of HAMLET Prince of Denmarke. " <>
                 "[The Tragical History of Hamlet, Prince of Denmark]. Shakespeare, William. " <>
                 "London. Ling, Nicholas; Trundell, John. 1603. 4º. Usual abbreviation: Q1. " <>
                 "Often referred to as “bad quarto”. Printer: Simmes, Valentine.",
               "COMEDIES, HISTORIES, & TRAGEDIES. Shakespeare, William. London. " <>
                 "Blount, Edward; Smethwick, John; Jaggard, Isaac; Aspley, William. 1623. 2º. " <>
                 "Usual abbreviation: F1. Also referred to as First Folio."
             ]

      assert witness_lines(mudarra) == [
               "Veinticuatro parte perfeta de las comedias del Fénix de España Frey Lope Félix de Vega Carpio.",
               "El bastardo Mudarra: tragicomedia."
             ]

      assert [%{origin: "filemaker", filemaker_id: "T03:33"} | _] = Witnesses.list_for_play(hamlet.id)
    end

    # As S4 learned: the play's filemaker rows alone are no marker, since a curator may
    # delete every one of them.
    test "a re-run skips a play already imported, even with every witness deleted", %{hamlet: hamlet} do
      run("playcode.import.witnesses", ["--path", @witnesses])
      for w <- Witnesses.list_for_play(hamlet.id), do: {:ok, _} = Witnesses.delete_witness(w)

      out = run("playcode.import.witnesses", ["--path", @witnesses])

      assert out =~ "already imported: 2 plays"
      assert out =~ "created 0 witnesses"
      assert witness_lines(hamlet) == []
    end

    test "an archived play is left out", %{mudarra: mudarra} do
      {:ok, _} = Catalogue.delete_play(mudarra)
      run("playcode.import.witnesses", ["--path", @witnesses])
      assert witness_lines(mudarra) == []
    end

    test "a missing dump is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.witnesses", ["--path", "test/fixtures/filemaker/nope"])
      end
    end
  end
```

- [ ] **Step 3: Run them and watch them fail**

Run: `mix test test/playcode/import/witnesses_test.exs test/playcode/witnesses/oracle_test.exs test/mix/tasks_test.exs`
Expected: compilation error, `module Playcode.Import.Witnesses is not available`.

- [ ] **Step 4: Write the smallest implementation** — create `lib/playcode/import/witnesses.ex`:

```elixir
defmodule Playcode.Import.Witnesses do
  @moduledoc """
  The one-time move of FileMaker's witnesses into Playcode (S3). Spec: "Import" in
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

  `load/1` reads `T03` and `T03.2`. `plan/2` decides what to write: it reads the database
  but never writes. `apply_plan/2` writes the plan in one transaction.

  A play the import has written to before (a `filemaker` witness, or its "import" row in
  the activity log, which outlives the witnesses) is skipped whole, so a re-run picks up
  the plays added since without undoing a curator's edits or deletions.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Import.{FilemakerSync, FilemakerXml}
  alias Playcode.Repo
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness

  @default_dir "doc/ctce_dades"

  @files [witnesses: "T03_ObraTestimonio.xml", attributions: "T03.2_Atribucion.xml"]

  # T03.1 by id. "No consta" (4, 7) is its parent; the deepest level a record sets wins.
  @types %{
    "2" => "manuscript",
    "3" => "early_edition",
    "4" => "manuscript",
    "5" => "autograph",
    "6" => "copy",
    "7" => "early_edition",
    "8" => "collection",
    "9" => "loose",
    "10" => "collection_single_author",
    "11" => "collection_several_authors"
  }

  # T03 rows that are FileMaker's own tests: "TituloTestimonio", siglum "TES".
  @test_records ~w(32)

  @described ~w(ObrTes_TituloTestimonio ObrTes_TituloNormalizado ObrTes_Observacion)

  def default_dir, do: @default_dir

  @doc "Reads the two tables from `dir`."
  def load(dir) do
    Enum.reduce_while(@files, {:ok, %{}}, fn {key, file}, {:ok, data} ->
      case FilemakerXml.read(Path.join(dir, file)) do
        {:ok, rows} -> {:cont, {:ok, Map.put(data, key, rows)}}
        {:error, reason} -> {:halt, {:error, {file, reason}}}
      end
    end)
  end

  @doc "Attribution names by id, from `T03.2`."
  def attributions(data),
    do: Map.new(data.attributions, &{&1["_kp_IdAtribucion"], value(&1, "_tc_Atr_Atribucion")})

  @doc "Why a `T03` row is not imported whatever play it names: `:test_record`, `:empty`, or nil."
  def skip_reason(row) do
    cond do
      row["_kp_IdObraTestimonio"] in @test_records -> :test_record
      Enum.all?(@described, &is_nil(value(row, &1))) -> :empty
      true -> nil
    end
  end

  @doc "A `T03` row as witness attributes, its attribution looked up in `attributions`."
  def witness_attrs(row, attributions) do
    %{
      siglum: value(row, "ObrTes_Siglas"),
      title: value(row, "ObrTes_TituloTestimonio"),
      normalized_title: value(row, "ObrTes_TituloNormalizado"),
      attribution: attributions[value(row, "_k_IdAtribucion")],
      pub_place: value(row, "ObrTes_Ciudad"),
      publisher: value(row, "ObrTes_Editorial"),
      date: value(row, "ObrTes_Anyo"),
      format: value(row, "ObrTes_Formato"),
      witness_type:
        Enum.find_value(
          ~w(_k_IdTesTip_Nivel3 _k_IdTesTip_Nivel2 _k_IdTesTip_Nivel1),
          &@types[value(row, &1)]
        ),
      shelfmark: value(row, "ObrTes_SignaturaFI"),
      note: value(row, "ObrTes_Observacion")
    }
  end

  @doc "What `apply_plan/2` would write. Reads the database, writes nothing. See the moduledoc."
  def plan(data, plays) do
    attributions = attributions(data)

    context = %{
      by_code: Enum.group_by(plays, &FilemakerSync.base_code(&1.code)),
      imported: imported_play_ids(),
      sigla: existing_sigla()
    }

    empty = %{witnesses: [], already_imported: MapSet.new(), skipped: %{}, dropped: [], not_held: 0}

    acc =
      data.witnesses
      |> Enum.sort_by(&String.to_integer(&1["_kp_IdObraTestimonio"]))
      |> Enum.reduce(empty, fn row, acc ->
        ref = "T03:" <> row["_kp_IdObraTestimonio"]

        case skip_reason(row) do
          nil -> place(acc, context, ref, witness_attrs(row, attributions), row["_k_IdObraTitulo"])
          reason -> skip(acc, reason, ref)
        end
      end)

    %{
      witnesses: Enum.reverse(acc.witnesses),
      already_imported: acc.already_imported |> MapSet.to_list() |> Enum.sort(),
      skipped: Map.new(acc.skipped, fn {reason, refs} -> {reason, Enum.reverse(refs)} end),
      dropped: Enum.reverse(acc.dropped),
      not_held: acc.not_held
    }
  end

  @doc """
  Writes the plan in one transaction: each play's witnesses in FileMaker's order, after any
  it already has, then one activity-log entry per play. Returns `{:ok, %{witnesses: n}}`.
  """
  def apply_plan(plan, opts \\ []) do
    Repo.transaction(
      fn ->
        Enum.each(plan.witnesses, fn w ->
          {:ok, _} =
            Witnesses.create_witness(
              Map.put(w, :origin, "filemaker"),
              %Witness{filemaker_id: w.filemaker_id}
            )
        end)

        plan.witnesses
        |> Enum.group_by(& &1.play_id)
        |> Enum.each(fn {play_id, witnesses} ->
          ActivityLog.log!(%{
            user_id: opts[:user_id],
            play_id: play_id,
            action: "import",
            resource_type: "play_witness",
            resource_id: play_id,
            changes: %{"witnesses" => length(witnesses)},
            metadata: %{"source" => "filemaker"}
          })
        end)

        %{witnesses: length(plan.witnesses)}
      end,
      timeout: :infinity
    )
  end

  @doc "The plan as lines of text, for the mix task and the release."
  def report(plan) do
    per_play =
      plan.witnesses
      |> Enum.group_by(& &1.code)
      |> Enum.sort()
      |> Enum.map(fn {code, witnesses} -> "#{code}  #{length(witnesses)} witnesses" end)

    plays = plan.witnesses |> Enum.uniq_by(& &1.play_id) |> length()

    skipped =
      for {reason, refs} <- Enum.sort(plan.skipped) do
        "skipped, #{reason}: #{length(refs)}  #{Enum.join(refs, ", ")}"
      end

    per_play ++
      [
        "",
        "witnesses: #{length(plan.witnesses)} on #{plays} plays",
        "attribution dropped: #{length(plan.dropped)}  #{Enum.join(plan.dropped, ", ")}"
      ] ++
      skipped ++
      [
        "already imported: #{length(plan.already_imported)} plays #{Enum.join(plan.already_imported, ", ")}",
        "witnesses on versions not held: #{plan.not_held}"
      ]
  end

  defp place(acc, context, ref, attrs, version) do
    case Map.get(context.by_code, version_code(version), []) do
      [] -> %{acc | not_held: acc.not_held + 1}
      plays -> Enum.reduce(plays, acc, &place_on(&2, context, ref, attrs, &1))
    end
  end

  defp place_on(acc, context, ref, attrs, play) do
    cond do
      MapSet.member?(context.imported, play.id) ->
        %{acc | already_imported: MapSet.put(acc.already_imported, play.code)}

      attrs.siglum && MapSet.member?(context.sigla, {play.id, attrs.siglum}) ->
        skip(acc, :siglum_taken, "#{ref} on #{play.code}")

      true ->
        {attrs, acc} = drop_misattribution(attrs, acc, "#{ref} on #{play.code}", play)
        witness = Map.merge(attrs, %{play_id: play.id, code: play.code, filemaker_id: ref})
        %{acc | witnesses: [witness | acc.witnesses]}
    end
  end

  # Jodelle is FileMaker's first attribution record, left on witnesses of Spanish plays by
  # the picker's default (the spec, "Attributions dropped"). On his own plays it is right.
  defp drop_misattribution(attrs, acc, label, play) do
    if is_binary(attrs.attribution) and attrs.attribution =~ "Jodelle" and
         not String.contains?(play.author_name || "", "Jodelle") do
      {%{attrs | attribution: nil}, %{acc | dropped: [label | acc.dropped]}}
    else
      {attrs, acc}
    end
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

  defp value(row, field) do
    case row[field] do
      nil -> nil
      text -> if String.trim(text) == "", do: nil, else: String.trim(text)
    end
  end

  # A play is done once the import has written to it. Its filemaker witnesses alone are no
  # marker: a curator may delete every one, and the next run must not bring them back. The
  # activity-log row apply_plan/2 writes per play survives that.
  defp imported_play_ids do
    logged =
      ActivityLog.Entry
      |> where([a], a.action == "import" and a.resource_type == "play_witness")
      |> select([a], a.play_id)

    Witness
    |> where([w], w.origin == "filemaker")
    |> select([w], w.play_id)
    |> union(^logged)
    |> Repo.all()
    |> MapSet.new()
  end

  # `{play_id, siglum}` for every witness the plays already have.
  defp existing_sigla do
    Witness
    |> where([w], not is_nil(w.siglum))
    |> select([w], {w.play_id, w.siglum})
    |> Repo.all()
    |> MapSet.new()
  end
end
```

Create `lib/mix/tasks/playcode.import.witnesses.ex`:

```elixir
defmodule Mix.Tasks.Playcode.Import.Witnesses do
  @shortdoc "Move FileMaker's witnesses into the plays we hold"

  @moduledoc """
  Reads FileMaker's witness tables (`T03`, `T03.2`) and gives the plays in the database
  their witnesses: S3's one-time import. Spec:
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

      mix playcode.import.witnesses --dry-run       # print the plan, write nothing
      mix playcode.import.witnesses                 # write it
      mix playcode.import.witnesses --path other/dir

  Re-running is safe: a play already imported is skipped whole, so a curator's edits and
  deletions stay. On Fly, use `Playcode.Release.import_witnesses/2`.
  """

  use Mix.Task

  alias Playcode.Import.{FilemakerSync, Witnesses}

  @switches [dry_run: :boolean, path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dir = opts[:path] || Witnesses.default_dir()

    case Witnesses.load(dir) do
      {:ok, data} ->
        plan = Witnesses.plan(data, FilemakerSync.all_plays())
        Enum.each(Witnesses.report(plan), fn line -> Mix.shell().info(line) end)

        if opts[:dry_run] do
          Mix.shell().info("\ndry run, nothing written")
        else
          {:ok, written} = Witnesses.apply_plan(plan)
          Mix.shell().info("\ncreated #{written.witnesses} witnesses")
        end

      {:error, {file, reason}} ->
        Mix.raise("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end
end
```

In `lib/playcode/release.ex`, change line 4 to `alias Playcode.Import.{Bibliography, FilemakerSync, Witnesses}`, and after `import_bibliography/2`:

```elixir
  @doc """
  S3's one-time witness import, for a release, which has no mix tasks. Copy
  `T03_ObraTestimonio.xml` and `T03.2_Atribucion.xml` onto the machine first
  (`fly ssh sftp shell`), then:

      bin/playcode rpc 'Playcode.Release.import_witnesses("/tmp/ctce", dry_run: true)'
      bin/playcode rpc 'Playcode.Release.import_witnesses("/tmp/ctce")'
  """
  def import_witnesses(dir, opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    case Witnesses.load(dir) do
      {:ok, data} ->
        plan = Witnesses.plan(data, FilemakerSync.all_plays())
        Enum.each(Witnesses.report(plan), &IO.puts/1)

        if opts[:dry_run] do
          IO.puts("dry run, nothing written")
        else
          {:ok, written} = Witnesses.apply_plan(plan)
          IO.puts("created #{written.witnesses} witnesses")
        end

      {:error, {file, reason}} ->
        IO.puts("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end
```

- [ ] **Step 5: Run them and watch them pass**

Run: `mix test test/playcode/import/witnesses_test.exs test/playcode/witnesses/oracle_test.exs test/mix/tasks_test.exs`
Expected: all pass. Then the whole dump:
Run: `mix test test/playcode/witnesses/oracle_test.exs --include slow`
Expected: pass. If it reports misses, read each record in `doc/ctce_dades/T03_ObraTestimonio.xml` before touching the renderer: a miss caused by FileMaker's own slip (a value FileMaker prints that is not a witness field) is recorded in the test as S4's oracle records `T12:2095`, with a comment naming the record; a miss caused by the renderer is a renderer bug.

- [ ] **Step 6: Refactor while green** — `load/1`, `version_code/1` and `value/2` repeat `Import.Bibliography`'s private helpers line for line. Leave the copies (two private five-line helpers do not earn a shared module), but if a third importer appears, that is the moment. Re-run Step 5's first command.

- [ ] **Step 7: Run it on dev** (spec, "Expected result"):

Run: `mix playcode.import.witnesses --dry-run 2>&1 | tail -8`
Expected:
```
witnesses: 508 on 106 plays
attribution dropped: 11  T03:… on EMOTHE0013_…, …
skipped, empty: 5  T03:14, T03:15, T03:62, T03:67, T03:600
skipped, test_record: 1  T03:32
already imported: 0 plays 
witnesses on versions not held: 87
```
If a figure differs, stop and find out why before writing (dev's plays may have changed since 2026-10-10); then record the real figures in the spec's "Expected result".

Run: `mix playcode.import.witnesses | tail -1` — expect `created 508 witnesses`; a second run — expect `already imported: 106 plays` and `created 0 witnesses`.

- [ ] **Step 8: Format, full suite, commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
git add lib/playcode/import/witnesses.ex lib/mix/tasks/playcode.import.witnesses.ex lib/playcode/release.ex test/fixtures/filemaker/witnesses test/playcode/import/witnesses_test.exs test/playcode/witnesses/oracle_test.exs test/mix/tasks_test.exs
git commit -m "feat(import): FileMaker's witnesses into the plays we hold, once

mix playcode.import.witnesses and Release.import_witnesses/2. Skips the test
and empty records, drops Jodelle's name where the picker left it on Spanish
plays, and skips a play already imported. On dev: 508 witnesses on 106 plays.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The Witnesses tab

**Files:**
- Create: `lib/playcode_web/live/admin/play_witnesses_live.ex`
- Modify: `lib/playcode_web/router.ex` (after `live "/plays/:id/sources", …`, line 163)
- Modify: `lib/playcode_web/components/layouts.ex` (the `active_tab` doc, line 106; a tab after Sources, near line 151)
- Modify: `lib/playcode_web/play_labels.ex` (after `bibliography_kind_options/0`, near line 191)
- Modify: `lib/playcode_web/live/admin/activity_log_live.ex` (`translate_resource_type/1`, line 134)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po` (through `mix gettext.extract --merge`)
- Test: `test/playcode_web/live/admin/play_witnesses_live_test.exs` (create), `test/playcode_web/authorization_test.exs`, `test/playcode_web/accessibility_test.exs`

**Interfaces:**
- Consumes: everything `Playcode.Witnesses` produces; `LiveHelpers.log_activity/5`, `LiveHelpers.put_gone_flash/1`
- Produces: `PlaycodeWeb.PlayLabels.witness_type_options/0 :: [{group_label, [{label, value}]}]`, `witness_type_label/1 :: String.t()`; route `/admin/plays/:id/witnesses`; `active_tab: :witnesses`

- [ ] **Step 1: Write the failing tests** — create `test/playcode_web/live/admin/play_witnesses_live_test.exs`:

```elixir
defmodule PlaycodeWeb.Admin.PlayWitnessesLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.Witnesses

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp sigla(play), do: for({attrs, _} <- xml_elements(export_tei(play), "witness"), do: attrs["n"])

  defp button(lv, witness, label),
    do: element(lv, "#witness-#{witness.id} button[aria-label='#{t(label)}']")

  defp add(lv, attrs) do
    lv |> element("button", t("Add witness")) |> render_click()
    lv |> form("#witness-form", witness: attrs) |> render_submit()
  end

  test "a witness added, moved, corrected and deleted here is what the play's TEI lists",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/witnesses")

    add(lv, %{"siglum" => "M", "title" => "El conde de Sex", "witness_type" => "copy"})
    add(lv, %{"siglum" => "S", "title" => "Parte treynta y una", "date" => "1638"})
    assert sigla(play) == ["M", "S"]

    [m, s] = Witnesses.list_for_play(play.id)
    lv |> button(s, "Move up") |> render_click()
    assert sigla(play) == ["S", "M"]

    lv |> button(m, "Edit") |> render_click()
    lv |> form("#witness-form", witness: %{"date" => "s. a."}) |> render_submit()
    assert xml_texts(export_tei(play), "date", within: "witness") == ["1638", "s. a."]

    lv |> button(s, "Delete") |> render_click()
    assert sigla(play) == ["M"]
  end

  test "the form shows the line as it will print, and says what is missing",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/witnesses")
    lv |> element("button", t("Add witness")) |> render_click()

    lv
    |> form("#witness-form", witness: %{"title" => "El conde de Sex", "shelfmark" => "16722"})
    |> render_change()

    assert lv |> element("#witness-preview") |> render() =~
             "<em>El conde de Sex</em>. Archivo: 16722."

    html =
      lv
      |> form("#witness-form", witness: %{"title" => "", "shelfmark" => "16722"})
      |> render_submit()

    assert html =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "needs a title, a normalised title or a note"
             )

    assert Witnesses.list_for_play(play.id) == []
  end

  # As for sources: an id from the browser that is not this play's witness changes
  # nothing, crashes nothing, and says so.
  test "a witness that is not this play's is neither edited, moved nor deleted",
       %{conn: conn, play: play} do
    {:ok, theirs} = Witnesses.create_witness(%{"play_id" => play_fixture().id, "title" => "Ajeno"})

    for event <- ~w(edit_witness move_up move_down delete_witness),
        id <- [theirs.id, Ecto.UUID.generate(), "not-an-id"] do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/witnesses")

      assert render_click(lv, event, %{"id" => id}) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"

      refute has_element?(lv, "#witness-form")
    end

    assert [%{title: "Ajeno"}] = Witnesses.list_for_play(theirs.play_id)
  end
end
```

In `test/playcode_web/authorization_test.exs`, add to `@routes` after the sources row:

```elixir
    {"/admin/plays/:id/witnesses", :active},
```

In `test/playcode_web/accessibility_test.exs`, add `/admin/plays/:id/witnesses` to `@pages` after `/admin/plays/:id/sources`, and to the click cases after the sources one:

```elixir
          {"/admin/plays/:id/witnesses", [{"button", t("Add witness")}]},
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/admin/play_witnesses_live_test.exs test/playcode_web/authorization_test.exs test/playcode_web/accessibility_test.exs`
Expected: failures with `no route found for GET /admin/plays/…/witnesses`.

- [ ] **Step 3: Write the smallest implementation**

Router (`lib/playcode_web/router.ex`), after the sources route:

```elixir
      live "/plays/:id/witnesses", PlayWitnessesLive, :index
```

Context bar (`lib/playcode_web/components/layouts.ex`): add `:witnesses` to the `active_tab` doc list after `:sources`, and after the Sources `<.link>`:

```heex
          <.link
            navigate={~p"/admin/plays/#{@play.id}/witnesses"}
            class={ctx_tab_class(@active_tab == :witnesses)}
          >
            {gettext("Witnesses")}
          </.link>
```

Labels (`lib/playcode_web/play_labels.ex`), after `bibliography_kind_options/0`:

```elixir
  @doc "The witness types for a form's select, grouped as FileMaker's tree: manuscripts, then early editions."
  def witness_type_options do
    [
      {gettext("Manuscript"),
       [
         {gettext("Manuscript"), "manuscript"},
         {gettext("Autograph"), "autograph"},
         {gettext("Copy"), "copy"}
       ]},
      {gettext("Early edition"),
       [
         {gettext("Early edition"), "early_edition"},
         {gettext("Collection"), "collection"},
         {gettext("Collection of one author"), "collection_single_author"},
         {gettext("Collection of several authors"), "collection_several_authors"},
         {gettext("Suelta"), "loose"}
       ]}
    ]
  end

  @doc "A witness type's label, as the admin list shows it beside the siglum. Never public."
  def witness_type_label(type) do
    witness_type_options()
    |> Enum.flat_map(fn {_group, options} -> options end)
    |> Enum.find_value("", fn {label, value} -> if value == type, do: label end)
  end
```

Activity log (`lib/playcode_web/live/admin/activity_log_live.ex`), in `translate_resource_type/1` after the `"play_bibliography"` clause:

```elixir
      "play_witness" -> gettext("witness")
```

Create `lib/playcode_web/live/admin/play_witnesses_live.ex`:

```elixir
defmodule PlaycodeWeb.Admin.PlayWitnessesLive do
  @moduledoc """
  /admin/plays/:id/witnesses: the manuscripts and early printings the play's text survives
  in (S3), in order, each previewed as the public pages print it. Spec:
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Witnesses")}")
     |> assign(:play, play)
     |> assign(:witnesses, Witnesses.list_for_play(play.id))
     |> assign(editing: nil, form: nil)
     |> assign(:play_context, %{play: play, active_tab: :witnesses})}
  end

  @impl true
  def handle_event("new_witness", _, socket) do
    {:noreply, edit(socket, :new, %Witness{play_id: socket.assigns.play.id})}
  end

  def handle_event("edit_witness", %{"id" => id}, socket) do
    with_witness(socket, id, &edit(socket, &1, &1))
  end

  def handle_event("cancel_edit", _, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate_witness", %{"witness" => params}, socket) do
    changeset =
      socket |> editing_base() |> Witnesses.change_witness(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save_witness", %{"witness" => params}, socket) do
    {action, result} =
      case socket.assigns.editing do
        :new ->
          {"create", Witnesses.create_witness(Map.put(params, "play_id", socket.assigns.play.id))}

        witness ->
          {"update", Witnesses.update_witness(witness, params)}
      end

    case result do
      {:ok, witness} ->
        log(socket, action, witness)

        message =
          if action == "create", do: gettext("Witness added."), else: gettext("Witness updated.")

        {:noreply,
         socket |> reload() |> assign(editing: nil, form: nil) |> put_flash(:info, message)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("move_up", %{"id" => id}, socket), do: move(socket, id, :up)
  def handle_event("move_down", %{"id" => id}, socket), do: move(socket, id, :down)

  def handle_event("delete_witness", %{"id" => id}, socket) do
    with_witness(socket, id, fn witness ->
      {:ok, _} = Witnesses.delete_witness(witness)
      log(socket, "delete", witness)
      socket |> reload() |> put_flash(:info, gettext("Witness deleted."))
    end)
  end

  defp move(socket, id, direction) do
    with_witness(socket, id, fn witness ->
      :ok = Witnesses.move_witness(witness, direction)
      reload(socket)
    end)
  end

  defp edit(socket, editing, witness),
    do: assign(socket, editing: editing, form: to_form(Witnesses.change_witness(witness)))

  defp editing_base(%{assigns: %{editing: :new, play: play}}), do: %Witness{play_id: play.id}
  defp editing_base(%{assigns: %{editing: witness}}), do: witness

  # The witness the event named, or the list reloaded with a flash when it is not this
  # play's: see LiveHelpers.put_gone_flash/1.
  defp with_witness(socket, id, fun) do
    case Witnesses.get_witness(socket.assigns.play.id, id) do
      nil -> {:noreply, socket |> reload() |> LiveHelpers.put_gone_flash()}
      witness -> {:noreply, fun.(witness)}
    end
  end

  defp reload(socket),
    do: assign(socket, :witnesses, Witnesses.list_for_play(socket.assigns.play.id))

  defp log(socket, action, witness) do
    LiveHelpers.log_activity(socket, action, "play_witness", witness.id, %{
      siglum: witness.siglum,
      title: witness.title || witness.normalized_title
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Witnesses")}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("The manuscripts and early printings the text survives in.")}
          </p>
        </div>
        <button :if={@editing == nil} phx-click="new_witness" class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add witness")}
        </button>
      </div>

      <div :if={@form} class="mb-6 rounded-box border border-primary/30 bg-base-100 p-5 shadow-md">
        <h2 class="mb-4 text-sm font-semibold text-primary">
          {if @editing == :new, do: gettext("New witness"), else: gettext("Edit witness")}
        </h2>
        <.form for={@form} id="witness-form" phx-change="validate_witness" phx-submit="save_witness">
          <div class="grid grid-cols-1 gap-x-4 md:grid-cols-2">
            <.input field={@form[:siglum]} type="text" label={gettext("Siglum")} />
            <.input
              field={@form[:witness_type]}
              type="select"
              label={gettext("Type")}
              prompt={gettext("Not stated")}
              options={PlayLabels.witness_type_options()}
            />
            <.input field={@form[:title]} type="text" label={gettext("Title as printed")} />
            <.input field={@form[:normalized_title]} type="text" label={gettext("Normalised title")} />
            <.input field={@form[:attribution]} type="text" label={gettext("Attribution")} />
            <.input field={@form[:pub_place]} type="text" label={gettext("Place")} />
            <.input field={@form[:publisher]} type="text" label={gettext("Publisher")} />
            <.input field={@form[:date]} type="text" label={gettext("Date")} />
            <.input field={@form[:format]} type="text" label={gettext("Format")} />
            <.input field={@form[:shelfmark]} type="text" label={gettext("Shelfmark")} />
          </div>
          <.input field={@form[:note]} type="textarea" rows="3" label={gettext("Observation")} />
          <p class="mt-2 text-xs text-base-content/70">{gettext("As it will print")}</p>
          <p id="witness-preview" class="font-serif text-sm">
            {Witnesses.html(Ecto.Changeset.apply_changes(@form.source))}
          </p>
          <div class="mt-4 flex justify-end gap-2">
            <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
          </div>
        </.form>
      </div>

      <div :if={@witnesses == [] && @form == nil} class="py-12 text-center text-base-content/70">
        <.icon name="hero-book-open" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No witnesses yet.")}</p>
        <button phx-click="new_witness" class="btn btn-ghost btn-sm mt-3">
          {gettext("Add the first witness")}
        </button>
      </div>

      <ol class="space-y-3">
        <li
          :for={witness <- @witnesses}
          id={"witness-#{witness.id}"}
          class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 text-sm">
              <span :if={witness.siglum} class="badge badge-ghost badge-sm mr-1 font-mono">
                {witness.siglum}
              </span>
              <span :if={witness.witness_type} class="text-xs text-base-content/70">
                {PlayLabels.witness_type_label(witness.witness_type)}
              </span>
              <p class="mt-1 font-serif">{Witnesses.html(witness)}</p>
            </div>
            <div class="flex shrink-0 gap-1">
              <button
                phx-click="move_up"
                phx-value-id={witness.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Move up")}
              >
                <.icon name="hero-arrow-up-micro" class="size-3.5" />
              </button>
              <button
                phx-click="move_down"
                phx-value-id={witness.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Move down")}
              >
                <.icon name="hero-arrow-down-micro" class="size-3.5" />
              </button>
              <button
                phx-click="edit_witness"
                phx-value-id={witness.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Edit")}
              >
                <.icon name="hero-pencil-square-micro" class="size-3.5" />
              </button>
              <button
                phx-click="delete_witness"
                phx-value-id={witness.id}
                data-confirm={gettext("Delete this witness?")}
                class="btn btn-ghost btn-xs text-error"
                aria-label={gettext("Delete")}
              >
                <.icon name="hero-trash-micro" class="size-3.5" />
              </button>
            </div>
          </div>
        </li>
      </ol>
    </div>
    """
  end
end
```

Translations: run `mix gettext.extract --merge`, then in `priv/gettext/es/LC_MESSAGES/default.po` give every new or emptied entry its Spanish, and for any entry the merge marked `fuzzy`, write the right Spanish and delete `, fuzzy`:

| msgid | msgstr |
|---|---|
| Witnesses | Testimonios |
| The manuscripts and early printings the text survives in. | Los manuscritos y ediciones antiguas en que se conserva el texto. |
| Add witness | Añadir testimonio |
| New witness | Nuevo testimonio |
| Edit witness | Editar testimonio |
| Siglum | Sigla |
| Type | Tipo |
| Not stated | No consta |
| Title as printed | Título del testimonio |
| Normalised title | Título normalizado |
| Attribution | Atribución |
| Format | Formato |
| Shelfmark | Signatura |
| Observation | Observación |
| As it will print | Así se imprimirá |
| Witness added. | Testimonio añadido. |
| Witness updated. | Testimonio actualizado. |
| Witness deleted. | Testimonio eliminado. |
| Delete this witness? | ¿Eliminar este testimonio? |
| No witnesses yet. | Aún no hay testimonios. |
| Add the first witness | Añadir el primer testimonio |
| witness | testimonio |
| Manuscript | Manuscrito |
| Autograph | Autógrafo |
| Copy | Copia |
| Early edition | Edición antigua |
| Collection | Colección |
| Collection of one author | Colección de autor |
| Collection of several authors | Colección de diversos autores |
| Suelta | Suelta |

An msgid that already existed before the merge keeps its translation; check it reads right here. Find the leftovers with `grep -n -B3 'msgstr ""$' priv/gettext/es/LC_MESSAGES/default.po | grep -A3 -E 'Witness|witness|Siglum|Shelfmark|Suelta'` and `grep -c fuzzy priv/gettext/es/LC_MESSAGES/default.po` (expect the same count as before the merge: `git stash -- priv/gettext && grep -c fuzzy priv/gettext/es/LC_MESSAGES/default.po; git stash pop`).

- [ ] **Step 4: Run them and watch them pass**

Run: `mix test test/playcode_web/live/admin/play_witnesses_live_test.exs test/playcode_web/authorization_test.exs test/playcode_web/accessibility_test.exs test/playcode_web/spanish_translations_test.exs test/playcode_web/live/admin/layout_test.exs`
Expected: all pass. Prove the gone-id test bites: in `with_witness/3`, call `Witnesses.list_for_play/1` and `Enum.find/2` by id ignoring the play (or simply use `Playcode.Repo.get(Witness, id)`) — expect the test to fail on `theirs.id`; restore.

- [ ] **Step 5: Refactor while green** — the page has one form, one list and one `with_witness/3` funnel; compare it with `PlaySourcesLive` and keep the shape. Run `mix compile --warnings-as-errors`. Re-run Step 4.

- [ ] **Step 6: Look at it.** `mix phx.server`, open `http://localhost:4000/admin/plays/<EMOTHE0010's id>/witnesses` (logged in), check the 14 imported witnesses list in order with sigla, a move, and the preview while typing. Stop the server.

- [ ] **Step 7: Format, full suite, commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
git add lib/playcode_web/live/admin/play_witnesses_live.ex lib/playcode_web/router.ex lib/playcode_web/components/layouts.ex lib/playcode_web/play_labels.ex lib/playcode_web/live/admin/activity_log_live.ex priv/gettext test/playcode_web/live/admin/play_witnesses_live_test.exs test/playcode_web/authorization_test.exs test/playcode_web/accessibility_test.exs
git commit -m "feat(admin): a Witnesses tab to add, edit, reorder and delete a play's witnesses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Witnesses on `/plays/:code` and the static site

**Files:**
- Modify: `lib/playcode_web/live/play_show_live.ex` (aliases; `build_metadata_sections/2` near line 510; a section before `#meta-bibliography`, near line 422)
- Modify: `lib/playcode/export/static_site/components.ex` (rail near line 163; a `witnesses/1` component beside `bibliography/1`, near line 230)
- Modify: `lib/playcode/export/static_site/pages/title.html.heex` (before `<Components.bibliography … />`, line 40)
- Modify: `priv/gettext/es/LC_MESSAGES/default.po` if the merge adds a reference only (no new msgid: "Witnesses" exists from Task 5)
- Test: `test/playcode_web/live/play_show_live_test.exs`, `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: `Play.witnesses` (preloaded by `with_all/2`), `Witnesses.html/1`
- Produces: `#meta-witnesses` on `/plays/:code`; `#witnesses` on the title page and `index.html#witnesses` in the rail

- [ ] **Step 1: Write the failing tests** — in `test/playcode_web/live/play_show_live_test.exs`, add after `describe "the bibliography panel"`:

```elixir
  describe "the witnesses panel" do
    test "is absent when the play has none", %{conn: conn} do
      play = TestFixtures.mark_complete!(TestFixtures.play_fixture())
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      refute has_element?(view, "#meta-witnesses")
      refute has_element?(view, ~s(a[href="#meta-witnesses"]))
    end

    test "lists the witnesses as emothe.uv.es prints them, with a sidebar entry, no siglum or type",
         %{conn: conn} do
      play = TestFixtures.play_fixture()

      {:ok, _} =
        Playcode.Witnesses.create_witness(%{
          "play_id" => play.id,
          "siglum" => "Q1",
          "witness_type" => "loose",
          "title" => "THE Tragicall Historie of HAMLET",
          "date" => "1603"
        })

      {:ok, _} =
        Playcode.Witnesses.create_witness(%{
          "play_id" => play.id,
          "title" => "El conde de Sex",
          "shelfmark" => "16722"
        })

      TestFixtures.mark_complete!(play)
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      section = view |> element("#meta-witnesses") |> render()

      assert section =~ "<em>THE Tragicall Historie of HAMLET</em>. 1603."
      assert section =~ "<em>El conde de Sex</em>. Archivo: 16722."
      refute section =~ "Q1"
      refute section =~ PlaycodeWeb.PlayLabels.witness_type_label("loose")
      assert has_element?(view, ~s(a[href="#meta-witnesses"]), t("Witnesses"))
    end
  end
```

In `test/playcode/export/static_site_play_test.exs`, add before the final `end`:

```elixir
  test "the title page lists the witnesses in order, linked from the contents, without siglum or type" do
    play = import_tei!(tei(body: @two_acts))

    {:ok, _} =
      Playcode.Witnesses.create_witness(%{
        "play_id" => play.id,
        "siglum" => "Q1",
        "witness_type" => "loose",
        "title" => "THE Tragicall Historie of HAMLET",
        "date" => "1603"
      })

    {:ok, _} =
      Playcode.Witnesses.create_witness(%{
        "play_id" => play.id,
        "title" => "COMEDIES, HISTORIES, & TRAGEDIES",
        "date" => "1623"
      })

    dir = generate!([play], all: true)
    title = page(dir, play, "index.html")

    assert texts(title, "#witnesses li") == [
             "THE Tragicall Historie of HAMLET. 1603.",
             "COMEDIES, HISTORIES, & TRAGEDIES. 1623."
           ]

    refute LazyHTML.text(title) =~ "Q1"

    rail =
      dir
      |> page(play, "act-1.html")
      |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
      |> LazyHTML.attribute("href")

    assert "index.html#witnesses" in rail
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode_web/live/play_show_live_test.exs test/playcode/export/static_site_play_test.exs`
Expected: the two "lists the witnesses" tests fail (`#meta-witnesses` / `#witnesses li` not found); "is absent" passes already.

- [ ] **Step 3: Write the smallest implementation**

`lib/playcode_web/live/play_show_live.ex`: add `alias Playcode.Witnesses`. In `build_metadata_sections/2`, before the bibliography line:

```elixir
    |> maybe_add_section(play.witnesses != [], "meta-witnesses", gettext("Witnesses"))
```

Immediately before `<%!-- Bibliography: laid out like Study and Places, … --%>`:

```heex
          <%!-- Witnesses: emothe.uv.es's Testimonios, laid out like the bibliography --%>
          <section
            :if={@play.witnesses != []}
            id="meta-witnesses"
            class="mb-8 max-w-2xl mx-auto scroll-mt-20 text-sm"
          >
            <dl class="grid gap-x-4 gap-y-2 sm:grid-cols-[max-content_1fr]">
              <dt class="text-base-content/70">{gettext("Witnesses")}</dt>
              <dd class="min-w-0">
                <ul class="space-y-2">
                  <li
                    :for={witness <- @play.witnesses}
                    class="pl-6 -indent-6 font-serif leading-relaxed"
                  >
                    {Witnesses.html(witness)}
                  </li>
                </ul>
              </dd>
            </dl>
          </section>
```

`lib/playcode/export/static_site/components.ex`: add `alias Playcode.Witnesses` with the other aliases; in the rail, before `<li :if={@edition.bibliography != []}>`:

```heex
      <li :if={@edition.play.witnesses != []}>
        <a href="index.html#witnesses">Witnesses</a>
      </li>
```

and, before `attr :groups, :list, required: true` of `bibliography/1`:

```elixir
  attr :play, :map, required: true

  # The bibliography's class gives the hanging indent; no CSS of its own.
  def witnesses(assigns) do
    ~H"""
    <section :if={@play.witnesses != []} id="witnesses" class="bibliography">
      <h2>Witnesses</h2>
      <ul>
        <li :for={witness <- @play.witnesses}>{Witnesses.html(witness)}</li>
      </ul>
    </section>
    """
  end
```

`lib/playcode/export/static_site/pages/title.html.heex`: before `<Components.bibliography groups={@edition.bibliography} />`:

```heex
    <Components.witnesses play={@edition.play} />
```

Run `mix gettext.extract --merge` and check `git diff priv/gettext` adds references only.

- [ ] **Step 4: Run them and watch them pass**

Run: `mix test test/playcode_web/live/play_show_live_test.exs test/playcode/export/static_site_play_test.exs test/playcode/export/static_site test/playcode_web/accessibility_test.exs`
Expected: all pass (the accessibility test renders `/plays/:code` too; its fixture play has no witnesses, so add none there).

- [ ] **Step 5: Refactor while green** — the show page's section copies the bibliography's markup; keep it (two sections, two shapes of data). Re-run Step 4.

- [ ] **Step 6: Look at it.** `mix phx.server`; open `http://localhost:4000/plays/<EMOTHE0010's code>` and the sidebar's Witnesses entry; in `/admin/export`, Generate, then Preview `plays/<code>/index.html#witnesses`. The amber dots after Task 4's import are expected: the import moved every imported play's `content_version`. Stop the server.

- [ ] **Step 7: Format, full suite, commit**

```bash
mix format && mix compile --warnings-as-errors && mix test
git add lib/playcode_web/live/play_show_live.ex lib/playcode/export/static_site/components.ex lib/playcode/export/static_site/pages/title.html.heex priv/gettext test/playcode_web/live/play_show_live_test.exs test/playcode/export/static_site_play_test.exs
git commit -m "feat(public): a play's witnesses on /plays/:code and the static site's title page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Docs and the full check

**Files:**
- Modify: `CLAUDE.md`, `docs/architecture.md`, `docs/backlog.md`, `docs/history.md`
- Modify: `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`
- Modify: `docs/superpowers/specs/2026-10-10-s3-witnesses-design.md` (status, and "Expected result" if Task 4 Step 7 measured different figures)

- [ ] **Step 1: CLAUDE.md and `docs/`** — make these edits, each a line or two in the house style (CLAUDE.md keeps the schema, the TEI mapping and the commands; the file map and routes are in `docs/architecture.md`, open work in `docs/backlog.md`, done work in `docs/history.md`):
  - `docs/architecture.md`, *Project Structure*: under `lib/playcode/`, `witnesses.ex  # A play's witnesses (S3): CRUD, order, the printed line, TEI id and type` and `witnesses/witness.ex  # One manuscript or early printing, with its siglum`; under `import/`, `witnesses.ex  # S3's one-time FileMaker witness import`; under `live/admin/`, `play_witnesses_live.ex  # Admin: /admin/plays/:id/witnesses - a play's witnesses`.
  - CLAUDE.md, *Database Schema*: a `play_witnesses` bullet — the columns, `position`, `origin`, unique `(play_id, siglum)`, the trigger, "printed as emothe.uv.es prints *Testimonios*; siglum and type are never public".
  - `docs/architecture.md`, *Routes / Admin*: `GET /admin/plays/:id/witnesses` - A play's witnesses: add, edit, reorder, delete, previewed as printed (`:view_admin`).
  - CLAUDE.md, *TEI-XML Format*: `sourceDesc/listWit/witness` -> witnesses (`@n` the siglum, `@xml:id` the siglum or `wit-` + siglum; `bibl@type`/`@subtype` the type); a siglum the play already has is skipped.
  - `docs/backlog.md`, *Found by the corpus round trip*: move the `sourceDesc/listWit/witness` item to `docs/history.md`, ticked, pointing at the spec.
  - CLAUDE.md, *Getting Started*: after the bibliography block, `mix playcode.import.witnesses --dry-run` / `mix playcode.import.witnesses` (S3, `T03` and `T03.2` under `doc/ctce_dades/`; on Fly `Playcode.Release.import_witnesses/2`).
  - `docs/backlog.md`, *FileMaker import (S3, S5-S8)*: S3 done (a line in `docs/history.md`); the rest stays.

- [ ] **Step 2: The roadmap** — S3's status row: `**done** 2026-10-1x — ../specs/2026-10-10-s3-witnesses-design.md`, with the commit range (`git log --oneline main..s3-witnesses`).

- [ ] **Step 3: The spec** — `**Status:** implemented, <date> (<first>..<last>)`.

- [ ] **Step 4: The full check**

```bash
mix format --check-formatted && mix compile --warnings-as-errors && mix test
mix test --include slow test/playcode/export/tei_validator_test.exs test/playcode/witnesses/oracle_test.exs test/playcode/roundtrip_test.exs
node --test test/js/*.test.mjs
```
Expected: all green; paste the summary lines into the final report.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/architecture.md docs/backlog.md docs/history.md docs/superpowers/plans/2026-08-01-filemaker-import-slices.md docs/superpowers/specs/2026-10-10-s3-witnesses-design.md
git commit -m "docs: S3 witnesses in CLAUDE.md, docs/, the roadmap and the spec

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Then hand over with superpowers:finishing-a-development-branch.
