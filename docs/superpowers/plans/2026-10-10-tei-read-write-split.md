# TEI Read/Write Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reading a TEI file becomes a pure function (`TeiParser.parse_file/1`, file to plain data) and writing it a separate one (`TeiImport`, data to rows in one transaction), with nothing a user, caller or test can observe changing.

**Architecture:** Two modules, no facade. The current `Playcode.Import.TeiParser` is first renamed `Playcode.Import.TeiImport` (callers, tests and docs re-pointed, no logic). Then the reading half is pulled out into a new, pure `Playcode.Import.TeiParser`, and `TeiImport` keeps the public API (`import_file/1`, `preview_import/1`, `mixed_ownership_total/1`), the preview counts and the writes. A golden master (every corpus play's TEI export and rows, dumped before and after) proves the split changed nothing.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8, Ecto + PostgreSQL, Saxy (`Saxy.SimpleForm`), ExUnit.

**Spec:** `docs/superpowers/specs/2026-10-10-tei-read-write-split-design.md` (read it first; this plan argues from it).

## Global Constraints

- Branch `tei-read-write-split`, worked in a git worktree (`superpowers:using-git-worktrees`); never commit to `main`. The main checkout `/home/bogdan/Projects/playcode` holds the user's uncommitted edits to `CLAUDE.md`, `docs/backlog.md` and others: never touch, stage or commit them.
- The worktree lacks the git-ignored corpus. Symlink the main checkout's `test/fixtures/tei_files` into the worktree (it is git-ignored there too) so `mix test --include slow` sweeps the same files; the golden master reads `doc/tei_corpus` from the main checkout by absolute path.
- **Nothing observable changes.** The split commit (Task 3) edits no existing test file; its only test change is the new `test/playcode/import/tei_parser_test.exs`.
- `TeiParser` calls no `Repo` and no context function that reads or writes the database. Pure helpers are fine: `Places.slugify/1`, `Places.Place.authorities/0`, `Witnesses.type_from_tei/2`, `Play.valid_languages/0`, `Play.composition_year_range/0`.
- Public API after the split: `TeiParser.parse_file/1` only; `TeiImport.import_file/1`, `TeiImport.preview_import/1`, `TeiImport.mixed_ownership_total/1`. Error terms unchanged: `File.read/1`'s (`:enoent`), `{:xml_parse_error, _}`, `:encoding_error`, `:missing_tei_header`, a play `%Ecto.Changeset{}`, `{:division_create_failed, cs}`, `{:element_create_failed, type_atom, cs}`, `{:note_create_failed, cs}`.
- The golden master runs only in the scratch database `playcode_test_golden` (`MIX_ENV=test MIX_TEST_PARTITION=_golden`), never `playcode_dev`. Its script and output live in the scratchpad `/tmp/claude-1000/-home-bogdan-Projects-playcode/f84b3c39-8555-4e4c-906d-0e02add3e3ae/scratchpad` (called `$SCRATCH` below) and are never committed.
- TDD in CLAUDE.md's order: failing test, watch it fail, smallest implementation, watch it pass, **refactor while green**, then `mix test` (the whole suite).
- `mix format` after every task; `mix compile --warnings-as-errors` before every commit. Run mix plainly (`mix test`, never `export PATH=… && mix test`).
- Plans and specs under `docs/superpowers/` and `docs/history.md` are records: the rename does not rewrite them. `docs/static-site-improvements.md:13` names `tei_parser.ex` for how text is *read*, which stays true after the split: leave it.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_016rfo2oSmWLTfvMmhBx4FKF
  ```

## Review Focus

1. **Corpus shapes no hand-written test has**: an act's own elements around its scenes sharing one position counter, two `elenco` divisions, a `titlePage` among front divs, castItems repeating an xml_id with another name (the suffix), `who` naming nobody or one character twice, several notes at one offset, `<p>`/`<lg>` directly in a `div2` (dropped today, must stay dropped). Expected: byte-identical rows and export. Pinned by the golden master (Task 2 baseline, Task 3 diff), first pass and `--force` pass.
2. **Re-importing every corpus play** (reset, update in place, hand-entered rows kept). Expected: same rows as before the split. Pinned by the golden master's second pass.
3. **A row refused mid-text** (a stage direction holding a literal `<stage>` marker). Expected: `{:error, {:element_create_failed, :stage_direction, cs}}` and no play left behind. Pinned by a new test in Task 2.
4. **A file the importer refuses, previewed**: no `teiHeader`, or malformed XML. Expected: `preview_import/1` returns the same error the import would, no crash, now that preview walks the whole file. Pinned by a new test in Task 2.
5. **The reader reaching for the database** (a later `<app>`/`<lb/>` change adding a lookup). Expected: a test fails. Pinned by `tei_parser_test.exs` (Task 3), which runs with no sandbox checkout.

---

### Task 1: Rename `TeiParser` to `TeiImport`

No logic changes: the module, its test file and every reference get the new name, so that Task 3 can give `TeiParser` to the pure reader.

**Files:**
- Rename: `lib/playcode/import/tei_parser.ex` → `lib/playcode/import/tei_import.ex`
- Rename: `test/playcode/import/tei_parser_test.exs` → `test/playcode/import/tei_import_test.exs`
- Modify (name only): `lib/playcode_web/live/admin/import_live.ex`, `lib/playcode/import/tei_corpus.ex`, `lib/mix/tasks/playcode.import.tei.ex`, `lib/playcode/catalogue/play.ex` (moduledoc), `test/support/import_helpers.ex`, `test/playcode/import/tei_preview_test.exs`, `test/playcode/import/tei_reimport_test.exs`, `test/playcode/tei_roundtrip_test.exs`, `test/playcode/roundtrip_test.exs`, `test/playcode/export/tei_validator_test.exs`, `CLAUDE.md`, `docs/architecture.md`, `docs/word-import-feature.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `Playcode.Import.TeiImport` with today's `import_file/1`, `preview_import/1`, `mixed_ownership_total/1`; test module `Playcode.Import.TeiImportTest`. The name `Playcode.Import.TeiParser` is free.

- [ ] **Step 1: Set up the worktree's corpus link**

From the worktree root:

```bash
ln -s /home/bogdan/Projects/playcode/test/fixtures/tei_files test/fixtures/tei_files
git status --short   # expected: nothing (tei_files is git-ignored)
```

- [ ] **Step 2: Move the two files**

```bash
git mv lib/playcode/import/tei_parser.ex lib/playcode/import/tei_import.ex
git mv test/playcode/import/tei_parser_test.exs test/playcode/import/tei_import_test.exs
```

- [ ] **Step 3: Rename every reference**

```bash
git grep -l "TeiParser" -- lib test CLAUDE.md docs/architecture.md \
  | xargs sed -i 's/TeiParserTest/TeiImportTest/g; s/TeiParser/TeiImport/g'
sed -i 's#tei_parser_test\.exs#tei_import_test.exs#g; s#tei_parser\.ex#tei_import.ex#g' \
  CLAUDE.md docs/architecture.md docs/word-import-feature.md
```

- [ ] **Step 4: Check nothing stale is left**

Run: `git grep -n "TeiParser\|tei_parser"`
Expected: matches only in `docs/backlog.md` (the item Task 3 retires), `docs/history.md` (if any), `docs/static-site-improvements.md:13`, and files under `docs/superpowers/`. Anything in `lib/`, `test/`, `CLAUDE.md`, `docs/architecture.md` or `docs/word-import-feature.md` is a missed reference: rename it.

Then read the diff of `CLAUDE.md`: the four touched lines are the `tei_import_test.exs` example (TDD rules), `TeiImport.import_file/1` (outermost API), `lib/playcode/import/tei_import.ex` (`@platform_owned`) and `TeiImport.preview_import/1`.

- [ ] **Step 5: Refactor while green**

Nothing to tidy in a rename. Check `lib/playcode/import/tei_import.ex` line 1 reads `defmodule Playcode.Import.TeiImport do` and its moduledoc is unchanged (Task 3 rewrites it).

- [ ] **Step 6: Run the suite**

```bash
mix format
mix compile --warnings-as-errors
mix test 2>&1 | tail -5
```

Expected: compiles without warnings; `0 failures` (same test count as on `main`).

- [ ] **Step 7: Commit**

```bash
git add -A lib test CLAUDE.md docs/architecture.md docs/word-import-feature.md
git commit -m "refactor(import): rename TeiParser to TeiImport, ahead of the read/write split

The name TeiParser goes to the pure reader the next commits extract; TeiImport
keeps import_file/1, preview_import/1 and the writes. No logic changes.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016rfo2oSmWLTfvMmhBx4FKF"
```

---

### Task 2: Pin today's behaviour

Two paths no test covers yet get a characterization test, and the golden master records every corpus play as today's code imports it. Both run before the split, against unchanged code.

**Files:**
- Modify: `test/playcode/import/tei_import_test.exs` (one test in `describe "a file that cannot become a play"`)
- Modify: `test/playcode/import/tei_preview_test.exs` (one test, one import)
- Create (scratch, never committed): `$SCRATCH/golden_dump.exs`, output under `$SCRATCH/golden/before/`

**Interfaces:**
- Consumes: `TeiImport.import_file/1`, `TeiImport.preview_import/1` (Task 1); `Playcode.Import.TeiCorpus.collect_files/1`, `import_all/2`; `Playcode.Export.TeiXml.generate/1`.
- Produces: `$SCRATCH/golden/before/{first,again}/` (per play: `rows/<CODE>.rows`, `tei/<CODE>.xml`; plus `places.rows` and `import.txt`), which Task 3 diffs against.

- [ ] **Step 1: Write the rollback test**

In `test/playcode/import/tei_import_test.exs`, inside `describe "a file that cannot become a play"`, after `"a teiHeader with no title fails validation"`:

```elixir
    # Nothing of a file is kept when one of its rows is refused: not the play, not the
    # rows written before it. A stage direction is a stage already, so the changeset
    # refuses a <stage> marker in one.
    test "a row the database refuses rolls the whole import back" do
      code = "TROLLBACK#{System.unique_integer([:positive])}"

      body =
        ~s(<div1 type="acto" n="1"><head>I</head><stage>&lt;stage&gt;Sale.&lt;/stage&gt;</stage></div1>)

      assert {:error, {:element_create_failed, :stage_direction, %Ecto.Changeset{}}} =
               TeiImport.import_file(write_tmp!(tei(code: code, body: body)))

      assert_raise Ecto.NoResultsError, fn -> Catalogue.get_play_by_code!(code) end
    end
```

- [ ] **Step 2: Write the preview test**

In `test/playcode/import/tei_preview_test.exs`, add below the aliases:

```elixir
  import Playcode.ImportHelpers, only: [write_tmp!: 1]
```

and at the end of the module:

```elixir
  test "a file the import would refuse, the preview refuses the same way" do
    assert {:error, :missing_tei_header} =
             TeiImport.preview_import(write_tmp!("<TEI><text><body/></text></TEI>"))

    assert {:error, {:xml_parse_error, _}} = TeiImport.preview_import(write_tmp!("<not valid>>>"))
  end
```

- [ ] **Step 3: Run both; they pass against today's code**

Run: `mix test test/playcode/import/tei_import_test.exs test/playcode/import/tei_preview_test.exs`
Expected: PASS. These pin existing behaviour, so they pass at once. If one fails, today's code behaves differently from what the test claims: read the failure, and correct the *test* to today's behaviour (never the code, in this task).

- [ ] **Step 4: Prove each test bites**

1. In `lib/playcode/import/tei_import.ex`, `import_stage_direction/5`, change `{:error, cs} -> Repo.rollback({:element_create_failed, :stage_direction, cs})` to `{:error, _cs} -> :ok`. Run the rollback test: expected FAIL (the import returns `{:ok, _}`). Put the line back.
2. In `preview_import/1`, change `nil -> {:error, :missing_tei_header}` to `nil -> {:ok, %{}}`. Run the preview test: expected FAIL. Put it back.

Run: `git diff lib/` — expected: empty.

- [ ] **Step 5: Refactor while green**

Read both tests as a stranger: the names say the rule, the comment says why. Nothing else to tidy.

- [ ] **Step 6: Run the suite and commit**

```bash
mix format
mix compile --warnings-as-errors
mix test 2>&1 | tail -5     # expected: 0 failures
git add test/playcode/import/tei_import_test.exs test/playcode/import/tei_preview_test.exs
git commit -m "test(import): pin a mid-text rollback and a refused file's preview

Both pass against today's importer; each was seen to fail with its line broken.
They hold the TEI read/write split to today's behaviour.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016rfo2oSmWLTfvMmhBx4FKF"
```

- [ ] **Step 7: Write the golden master script**

Write `$SCRATCH/golden_dump.exs`:

```elixir
# Golden master for the TEI read/write split
# (docs/superpowers/plans/2026-10-10-tei-read-write-split.md). Imports the corpus into an
# empty scratch database twice, as new plays and then with force, and after each pass dumps
# every play's TEI export and every row the importer writes, with ids and timestamps
# replaced by stable names. Two runs are compared with `diff -r`.
#
#   MIX_ENV=test MIX_TEST_PARTITION=_golden mix run golden_dump.exs OUT_DIR

defmodule Golden do
  @moduledoc false

  alias Playcode.Catalogue.Play
  alias Playcode.Export.TeiXml
  alias Playcode.Import.TeiCorpus
  alias Playcode.Repo

  @main "/home/bogdan/Projects/playcode"
  @play_tables ~w(play_editors play_sources play_editorial_notes play_witnesses characters
                  play_divisions play_elements play_notes play_places)

  def run(out) do
    # A real connection, outside the test sandbox's transaction.
    Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    files = TeiCorpus.collect_files(["#{@main}/doc/tei_corpus", "#{@main}/test/fixtures"])

    for {pass, force} <- [{"first", false}, {"again", true}] do
      dir = Path.join(out, pass)
      File.mkdir_p!(Path.join(dir, "tei"))
      File.mkdir_p!(Path.join(dir, "rows"))

      results = TeiCorpus.import_all(files, force: force)
      File.write!(Path.join(dir, "import.txt"), Enum.map_join(results, "\n", &summary/1))
      dump(dir)
    end
  end

  defp summary({:ok, code, _play}), do: "#{code} ok"
  defp summary({:skipped, code}), do: "#{code} skipped"
  defp summary({:error, code, reason}), do: "#{code} error #{inspect(reason)}"

  defp dump(dir) do
    places = rows("SELECT * FROM places", [])
    plays = rows("SELECT * FROM plays ORDER BY code", [])

    shared =
      Map.merge(
        Map.new(places, &{&1["id"], "place:#{&1["slug"]}"}),
        Map.new(plays, &{&1["id"], "play:#{&1["code"]}"})
      )

    write(
      Path.join(dir, "places.rows"),
      [{"places", places}, {"place_names", rows("SELECT * FROM place_names", [])}],
      shared
    )

    for play <- plays do
      tables = Map.new(@play_tables, &{&1, rows("SELECT * FROM #{&1} WHERE play_id = $1", [play["id"]])})

      joins =
        rows(
          "SELECT ec.* FROM element_characters ec JOIN play_elements e ON e.id = ec.element_id WHERE e.play_id = $1",
          [play["id"]]
        )

      write(
        Path.join([dir, "rows", play["code"] <> ".rows"]),
        [{"plays", [play]}, {"element_characters", joins} | Enum.map(@play_tables, &{&1, tables[&1]})],
        Map.merge(shared, play_names(tables))
      )

      File.write!(
        Path.join([dir, "tei", play["code"] <> ".xml"]),
        TeiXml.generate(Repo.get_by!(Play, code: play["code"]))
      )
    end
  end

  defp rows(sql, params) do
    %{columns: columns, rows: rows} = Repo.query!(sql, params)
    Enum.map(rows, &Map.new(Enum.zip(columns, &1)))
  end

  # Names for the rows of one play that other rows point at: a division by its path of
  # positions, an element by its path inside its division, a character by its xml_id.
  defp play_names(tables) do
    ctx = %{divisions: index(tables["play_divisions"]), elements: index(tables["play_elements"])}

    Map.new(
      Enum.map(tables["play_divisions"], &{&1["id"], division_name(&1["id"], ctx)}) ++
        Enum.map(tables["play_elements"], &{&1["id"], element_name(&1["id"], ctx)}) ++
        Enum.map(tables["characters"], &{&1["id"], "c:#{&1["xml_id"]}"})
    )
  end

  defp index(rows), do: Map.new(rows, &{&1["id"], &1})

  defp division_name(id, ctx) do
    d = ctx.divisions[id]
    parent = if d["parent_id"], do: division_name(d["parent_id"], ctx), else: ""
    "#{parent}/d#{d["position"]}"
  end

  defp element_name(id, ctx) do
    e = ctx.elements[id]

    parent =
      if e["parent_id"],
        do: element_name(e["parent_id"], ctx),
        else: division_name(e["division_id"], ctx)

    "#{parent}/e#{e["position"]}"
  end

  defp write(path, tables, names) do
    lines = for {table, rows} <- tables, row <- rows, do: table <> " " <> line(row, names)
    File.write!(path, lines |> Enum.sort() |> Enum.join("\n"))
  end

  # A row without its own id and timestamps, every uuid in it replaced by the name of the
  # row it points at. A uuid left raw in the dump points at a row nothing names.
  defp line(row, names) do
    row
    |> Map.drop(["id", "inserted_at", "updated_at"])
    |> Enum.map(fn {column, value} -> {column, Map.get(names, value, value)} end)
    |> Enum.sort()
    |> inspect(limit: :infinity, printable_limit: :infinity)
  end
end

[out] = System.argv()
Golden.run(out)
```

- [ ] **Step 8: Take the baseline**

From the worktree root, with Task 2's commit checked out (the code before the split):

```bash
export SCRATCH=/tmp/claude-1000/-home-bogdan-Projects-playcode/f84b3c39-8555-4e4c-906d-0e02add3e3ae/scratchpad
MIX_ENV=test MIX_TEST_PARTITION=_golden mix ecto.drop
MIX_ENV=test MIX_TEST_PARTITION=_golden mix ecto.create
MIX_ENV=test MIX_TEST_PARTITION=_golden mix ecto.migrate
MIX_ENV=test MIX_TEST_PARTITION=_golden mix run $SCRATCH/golden_dump.exs $SCRATCH/golden/before 2>&1 \
  | sed -E 's/^[0-9:. ]+//' > $SCRATCH/golden/before.log
```

Run it in the background (two corpus passes and 2 × ~390 exports: expect several minutes).

Expected, checked before moving on:
- `ls $SCRATCH/golden/before/first/tei | wc -l` and the same for `again`: about 390, equal.
- `grep -c " ok$" $SCRATCH/golden/before/first/import.txt`: about 390; `grep " error " …/import.txt` lists only files that are not TEI (FileMaker XML fixtures and the like).
- `grep -lE '<<[0-9]+, [0-9]+' $SCRATCH/golden/before/first/rows/*.rows $SCRATCH/golden/before/first/places.rows`: no file. A match is a raw uuid (inspected as `<<12, 200, …>>`) that no name replaced; uuids differ between runs, so it would make the diff useless. Name the table it points at in `play_names/1` or `shared`, and take the baseline again.
- `grep -c 'element_characters' $SCRATCH/golden/before/first/rows/EMOTHE0008.rows`: more than 0, and its `character_id` values read `c:…`.

If the plays count is 0, the import ran inside a rolled-back sandbox transaction: check the `checkout(sandbox: false)` line runs before the import.

---

### Task 3: Split reading from writing

**Files:**
- Create: `test/playcode/import/tei_parser_test.exs`
- Create: `lib/playcode/import/tei_parser.ex` (the pure reader)
- Modify: `lib/playcode/import/tei_import.ex` (reading removed; the writer)
- Modify: `docs/backlog.md`, `docs/history.md`, `docs/architecture.md` (separate commit, Step 13)

**Interfaces:**
- Consumes: `TeiImport` as Task 1 left it (line numbers below are of that file, identical to the pre-rename `tei_parser.ex`); `Playcode.ImportHelpers.tei/1` and `write_tmp!/1`.
- Produces:
  - `Playcode.Import.TeiParser.parse_file(path) :: {:ok, tei} | {:error, reason}`, `tei` as in the spec:
    ```elixir
    %{
      play: map,                    # extract_play_attrs/3's map
      editors: [%{person_name, role, organization, position}],   # principal has no :organization
      sources: [%{title, author, editor, editor_role, publisher, pub_place, pub_date, note, language, position}],
      witnesses: [map],             # witness_attrs/1's maps
      places: [%{attrs: %{"slug" => _, ...}, slug_declared: boolean, places: [place]}],
      settings: [%{slug, role, position, note}],
      characters: [%{xml_id, name, description, is_hidden, position}],
      editorial_notes: [%{section_type, heading, content, position}],
      divisions: [%{type, number, title, position, notes, elements, divisions}]
    }
    element: %{type, position, notes, elements} + its columns, + who: [xml_id] on a speech
    note: %{offset, n, type, term, body}
    ```
  - `Playcode.Import.TeiImport.import_file/1`, `preview_import/1`, `mixed_ownership_total/1`: unchanged signatures and results.

- [ ] **Step 1: Write the failing test**

Create `test/playcode/import/tei_parser_test.exs`:

```elixir
defmodule Playcode.Import.TeiParserTest do
  @moduledoc """
  Reading a TEI file, on its own. These tests check out no database connection, so a
  reader that reached for the database would fail them: reading is pure, and
  `TeiImport` does all the writing. What the reading means for a stored play is asserted
  through the import, in tei_import_test.exs and tei_roundtrip_test.exs.
  """
  use ExUnit.Case, async: true

  import Playcode.ImportHelpers, only: [tei: 1, write_tmp!: 1]

  alias Playcode.Import.TeiParser

  test "a play is read without the database" do
    xml =
      tei(
        code: "PURE01",
        front:
          ~s(<div type="elenco"><castList><castItem><role xml:id="ALB">Albano</role></castItem></castList></div>),
        body:
          ~s(<div1 type="acto" n="1"><head>Acto I</head><sp who="#ALB #ALB"><speaker>Albano</speaker><l n="1">Uno<note n="1">Glosa.</note> dos</l></sp></div1>)
      )

    assert {:ok, tei} = TeiParser.parse_file(write_tmp!(xml))

    assert %{code: "PURE01", title: "Test Play"} = tei.play
    assert [%{xml_id: "ALB", name: "Albano"}] = tei.characters

    assert [%{type: "elenco"}, %{type: "acto", title: "Acto I", elements: [speech]}] =
             tei.divisions

    assert %{type: "speech", speaker_label: "Albano", who: ["ALB", "ALB"], elements: [line]} =
             speech

    assert %{
             type: "verse_line",
             content: "Uno dos",
             line_number: 1,
             notes: [%{offset: 3, n: "1", body: "Glosa."}]
           } = line
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/playcode/import/tei_parser_test.exs`
Expected: FAIL with `UndefinedFunctionError` (`Playcode.Import.TeiParser.parse_file/1 is undefined (module Playcode.Import.TeiParser is not available)`).

- [ ] **Step 3: Create the reader**

Create `lib/playcode/import/tei_parser.ex`. Each `# verbatim: lines X-Y (…)` comment is replaced by those lines of `lib/playcode/import/tei_import.ex`, copied unchanged with their comments; the marker comment itself does not stay. Everything else is written as shown.

```elixir
defmodule Playcode.Import.TeiParser do
  @moduledoc """
  Reads a TEI-XML file into a plain description of a play, touching no database.

  `parse_file/1` returns everything `Playcode.Import.TeiImport` writes, in document order
  and with every position already counted:

      %{
        play: %{code: "EMOTHE0010", title: "…", …},
        editors: [%{person_name, role, organization, position}],
        sources: [%{title, author, editor, editor_role, publisher, pub_place, pub_date,
                    note, language, position}],
        witnesses: [%{siglum, witness_type, title, …}],
        places: [%{attrs: %{"slug" => …, …}, slug_declared: boolean, places: [place]}],
        settings: [%{slug, role, position, note}],
        characters: [%{xml_id, name, description, is_hidden, position}],
        editorial_notes: [%{section_type, heading, content, position}],
        divisions: [%{type, number, title, position, notes, elements, divisions}]
      }

  An element is `%{type, position, notes, elements}` plus its columns, and a speech's
  `who` the xml_ids it names. A note is `%{offset, n, type, term, body}`. Nothing here
  knows a row: ids, `play_id` and `origin` are the writer's.

  Handles UTF-16 encoded files (common in the EMOTHE corpus) by converting them to UTF-8
  before parsing with Saxy.
  """

  alias Playcode.Catalogue.Play
  alias Playcode.Places
  alias Playcode.Witnesses

  require Logger

  # verbatim: lines 39-69 (@title_small_words)

  @doc """
  Reads the play at `path`: `{:ok, tei}` (see the moduledoc) or `{:error, reason}`, the
  reason `File.read/1`'s, `{:xml_parse_error, _}`, `:encoding_error` or
  `:missing_tei_header`.
  """
  def parse_file(path) do
    with {:ok, {_name, _attrs, children}} <- read_tree(path) do
      case find_child(children, "teiHeader") do
        nil ->
          {:error, :missing_tei_header}

        {_name, _attrs, header} ->
          {:ok, Map.merge(header(header), text(find_child(children, "text")))}
      end
    end
  end

  # verbatim: lines 196-251 (read_tree/1, "# --- Encoding ---", normalize_encoding/1,
  # "# --- XML Parsing ---", parse_xml/1)

  # --- Header ---

  defp header(children) do
    file_desc = find_child(children, "fileDesc")
    profile_desc = find_child(children, "profileDesc")

    %{
      play: extract_play_attrs(file_desc, find_child(children, "encodingDesc"), profile_desc),
      editors: editors(file_desc),
      sources: sources(file_desc),
      witnesses: witnesses(file_desc),
      places: places(profile_desc),
      settings: settings(profile_desc)
    }
  end

  # verbatim: lines 348-613 (extract_play_attrs/3 through extract_encoding/1)

  # --- Editors ---

  # The principal investigator, the titleStmt's <editor>s, then the respStmts of the
  # titleStmt (from position 100) and of the editionStmt (from 200).
  defp editors(nil), do: []

  defp editors({_name, _attrs, children}) do
    title_stmt = find_child(children, "titleStmt")

    principal(title_stmt) ++
      title_editors(title_stmt) ++
      resp_stmt_editors(title_stmt, 100) ++
      resp_stmt_editors(find_child(children, "editionStmt"), 200)
  end

  defp principal(nil), do: []

  defp principal({_name, _attrs, children}) do
    case find_child(children, "principal") do
      nil -> []
      principal -> [%{person_name: text_content(principal), role: "principal", position: 0}]
    end
  end

  # <editor role="…"> in titleStmt: translators, researchers and the editor of the
  # critical edition the text is based on. Any other role (canon60) is skipped.
  defp title_editors(nil), do: []

  defp title_editors({_name, _attrs, children}) do
    children
    |> find_children("editor")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{_, attrs, ed_children}, idx} ->
      case editor_role(attr_value(attrs, "role")) do
        nil ->
          []

        role ->
          # Name may be in <persName> or direct text
          person_name =
            case find_child(ed_children, "persName") do
              nil -> text_content({"editor", attrs, ed_children})
              el -> text_content(el)
            end

          [
            %{
              person_name: person_name,
              role: role,
              organization: safe_text(find_child(ed_children, "orgName")),
              position: idx
            }
          ]
      end
    end)
  end

  defp editor_role("translator"), do: "translator"
  defp editor_role("traductor"), do: "translator"
  defp editor_role("researcher"), do: "researcher"
  defp editor_role("edicion_critica"), do: "critical_editor"
  defp editor_role(_role), do: nil

  # A respStmt with a <persName>, numbered from `first`; one without still takes its number.
  defp resp_stmt_editors(nil, _first), do: []

  defp resp_stmt_editors({_name, _attrs, children}, first) do
    children
    |> find_children("respStmt")
    |> Enum.with_index(first)
    |> Enum.flat_map(fn {{_name, _attrs, resp_children}, idx} ->
      case find_child(resp_children, "persName") do
        nil ->
          []

        person ->
          [
            %{
              person_name: text_content(person),
              role: resp_role(safe_text(find_child(resp_children, "resp"))),
              organization: safe_text(find_child(resp_children, "orgName")),
              position: idx
            }
          ]
      end
    end)
  end

  defp resp_role(resp) when is_binary(resp) do
    cond do
      String.contains?(resp, "Edición") -> "editor"
      String.contains?(resp, "Revisión") -> "reviewer"
      true -> "digital_editor"
    end
  end

  defp resp_role(nil), do: "digital_editor"

  # --- Sources ---

  # <bibl> directly under <sourceDesc>, or inside <listBibl>.
  defp sources(nil), do: []

  defp sources({_name, _attrs, children}) do
    case find_child(children, "sourceDesc") do
      nil ->
        []

      {_name, _attrs, desc_children} ->
        bibls =
          case find_child(desc_children, "listBibl") do
            nil -> find_children(desc_children, "bibl")
            {_name, _attrs, list_children} -> find_children(list_children, "bibl")
          end

        bibls |> Enum.with_index() |> Enum.map(&source/1)
    end
  end

  defp source({{_name, _attrs, children}, position}) do
    editor_el = find_child(children, "editor")

    %{
      title: safe_text(find_child(children, "title")),
      author: safe_text(find_child(children, "author")),
      editor: safe_text(editor_el),
      editor_role: editor_el && attr_value(elem(editor_el, 1), "role"),
      publisher: safe_text(find_child(children, "publisher")),
      pub_place: safe_text(find_child(children, "pubPlace")),
      pub_date: safe_text(find_child(children, "date")),
      note: safe_text(find_child(children, "note")),
      language: safe_text(find_child(children, "lang")),
      position: position
    }
  end

  # --- Witnesses ---

  # `sourceDesc/listWit`, nested lists read in order (S3). Which of them the play keeps
  # depends on the sigla it already has, so that is the writer's call.
  defp witnesses(nil), do: []

  defp witnesses({_name, _attrs, children}) do
    with {_name, _attrs, desc_children} <- find_child(children, "sourceDesc"),
         {_name, _attrs, _children} = list_wit <- find_child(desc_children, "listWit") do
      list_wit |> witness_elements() |> Enum.map(&witness_attrs/1)
    else
      nil -> []
    end
  end

  # verbatim: lines 815-864 (witness_elements/1, witness_attrs/1, typed/3)

  # --- Places ---

  # `listPlace` supplies the places and their containment; `setting` supplies this
  # play's links. Reading them separately is what keeps a pure container — Italia in
  # `<place xml:id="italia">…<place xml:id="roma">` — from becoming a setting.
  defp places(profile_desc) do
    case setting_desc_child(profile_desc, "listPlace") do
      nil -> []
      list_place -> list_places(list_place)
    end
  end

  defp settings(profile_desc) do
    case setting_desc_child(profile_desc, "setting") do
      nil -> []
      setting -> setting_links(setting)
    end
  end

  defp setting_desc_child(nil, _name), do: nil

  defp setting_desc_child({_name, _attrs, children}, name) do
    with {_n, _a, setting_children} <- find_child(children, "settingDesc"),
         do: find_child(setting_children, name)
  end

  defp list_places({_name, _attrs, children}) do
    for {"place", _, _} = place <- children, do: place(place)
  end

  # A place and the places nested in it. `slug_declared` is false when the slug was
  # derived from the name, which the writer warns about if it finds that slug taken.
  defp place({_name, attrs, children} = place_el) do
    declared_slug = attr_value(attrs, "xml:id")
    {latitude, longitude} = place_geo(children)

    place_attrs =
      %{
        "slug" => declared_slug || Places.slugify(first_place_name(children)),
        "type" => attr_value(attrs, "type") || "other",
        "is_fictional" => attr_value(attrs, "subtype") == "fictional",
        "latitude" => latitude,
        "longitude" => longitude,
        "note" => place_note(children),
        "names" => place_names(children)
      }
      |> Map.merge(place_idno(children))

    %{attrs: place_attrs, slug_declared: declared_slug != nil, places: list_places(place_el)}
  end

  # verbatim: lines 940-1028 (place_names/1, dedupe_preferred/1, first_place_name/1,
  # place_geo/1, place_idno/1, place_note/1)

  defp setting_links({_name, _attrs, children}) do
    children
    |> Enum.filter(&match?({"placeName", _, _}, &1))
    |> Enum.with_index()
    |> Enum.map(fn {{_n, attrs, name_children}, index} ->
      %{
        slug: attrs |> attr_value("ref") |> to_string() |> String.trim_leading("#"),
        role: attr_value(attrs, "ana") || "setting",
        position: index,
        note: setting_note(name_children)
      }
    end)
  end

  # verbatim: lines 1072-1079 (setting_note/1)

  # --- Text (front, body) ---

  defp text(nil), do: %{characters: [], editorial_notes: [], divisions: []}

  defp text({_name, _attrs, children}) do
    front = front(find_child(children, "front"))
    body = body(find_child(children, "body"), front.next_position)

    %{
      characters: front.characters,
      editorial_notes: front.editorial_notes,
      divisions: front.divisions ++ body
    }
  end

  # --- Front matter ---

  # Each <div> of the front takes a position, which the body's divisions continue; the
  # title page and anything else take none. A cast list is the play's characters and an
  # `elenco` division; any other div is an editorial note.
  defp front(nil), do: %{characters: [], editorial_notes: [], divisions: [], next_position: 0}

  defp front({_name, _attrs, children}) do
    divs =
      for({"div", attrs, div_children} <- children,
        do: {attr_value(attrs, "type") || "front", div_children}
      )
      |> Enum.with_index()

    %{
      characters:
        Enum.flat_map(divs, fn
          {{"elenco", div_children}, _pos} -> cast_list(find_child(div_children, "castList"))
          _other -> []
        end),
      divisions:
        for({{"elenco", div_children}, pos} <- divs, do: elenco_division(div_children, pos)),
      editorial_notes:
        Enum.flat_map(divs, fn
          {{"elenco", _div_children}, _pos} -> []
          {{type, div_children}, pos} -> editorial_note(type, div_children, pos)
        end),
      next_position: length(divs)
    }
  end

  defp elenco_division(children, pos) do
    %{
      type: "elenco",
      number: nil,
      title: safe_text(find_child(children, "head")),
      position: pos,
      notes: [],
      elements: [],
      divisions: []
    }
  end

  # Generic front matter div (dedication, editor's introduction, …), kept when it has
  # paragraphs.
  defp editorial_note(type, children, pos) do
    paragraphs =
      children
      |> find_children("p")
      |> Enum.map(&text_content/1)
      |> Enum.join("\n\n")

    if paragraphs == "" do
      []
    else
      [
        %{
          section_type: section_type(type),
          heading: safe_text(find_child(children, "head")),
          content: paragraphs,
          position: pos
        }
      ]
    end
  end

  defp section_type(type) when type in ~w(introduccion_editor dedicatoria argumento prologo),
    do: type

  defp section_type(_type), do: "nota"

  # --- Cast list ---

  defp cast_list(nil), do: []

  defp cast_list({_name, _attrs, children}) do
    children
    |> find_children("castItem")
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_name, attrs, item_children}, idx} ->
      case find_child(item_children, "role") do
        nil ->
          []

        {_role_name, role_attrs, _role_children} = role ->
          name = role |> text_content() |> String.trim()
          xml_id = attr_value(role_attrs, "xml:id") || attr_value(role_attrs, "id")

          [
            %{
              # Clean xml_id (some have newlines)
              xml_id: if(xml_id, do: String.trim(xml_id), else: name),
              name: name,
              description: safe_text(find_child(item_children, "roleDesc")),
              is_hidden: attr_value(attrs, "ana") == "oculto",
              position: idx
            }
          ]
      end
    end)
  end

  # --- Body (acts, scenes, speeches, etc.) ---

  defp body(nil, _first), do: []

  defp body({_name, _attrs, children}, first) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ["div1", "div"], &1))
    |> Enum.with_index(first)
    |> Enum.map(fn {{_name, attrs, act_children}, pos} ->
      {heading, notes} = text_and_notes(find_child(act_children, "head"))
      {elements, scenes} = act_content(act_children)

      %{
        type: (attr_value(attrs, "type") || "acto") |> String.downcase(),
        number: parse_int(attr_value(attrs, "n")),
        title: heading,
        position: pos,
        notes: notes,
        elements: elements,
        divisions: scenes
      }
    end)
  end

  # An act's own elements and its scenes. The act's elements and its scenes' share one
  # position counter: a scene's first element follows the last element before it.
  defp act_content(children) do
    {_el_pos, _scene_pos, elements, scenes} =
      Enum.reduce(children, {0, 0, [], []}, fn
        {"div2", attrs, scene_children}, {el_pos, scene_pos, elements, scenes} ->
          {heading, notes} = text_and_notes(find_child(scene_children, "head"))
          scene_elements = scene_content(scene_children, el_pos)

          scene = %{
            type: (attr_value(attrs, "type") || "escena") |> String.downcase(),
            number: parse_int(attr_value(attrs, "n")),
            title: heading,
            position: scene_pos,
            notes: notes,
            elements: scene_elements,
            divisions: []
          }

          {el_pos + length(scene_elements), scene_pos + 1, elements, [scene | scenes]}

        child, {el_pos, scene_pos, elements, scenes} = acc ->
          case act_element(child, el_pos) do
            nil -> acc
            element -> {el_pos + 1, scene_pos, [element | elements], scenes}
          end
      end)

    {Enum.reverse(elements), Enum.reverse(scenes)}
  end

  # An element directly in an act; nil for anything else (the head is the act's title).
  defp act_element({"sp", attrs, children}, pos), do: speech(attrs, children, pos)
  defp act_element({"stage", _, _} = stage, pos), do: stage_direction(stage, pos)
  defp act_element({"p", _, _} = para, pos), do: prose(para, pos)
  defp act_element({"lg", attrs, children}, pos), do: line_group(attrs, children, pos)
  defp act_element({"trailer", _, _} = trailer, pos), do: trailer(trailer, pos)
  defp act_element(_other, _pos), do: nil

  # A scene's speeches, stage directions and trailer, numbered from `first`. Nothing else
  # in a scene is read.
  defp scene_content(children, first) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ~w(sp stage trailer), &1))
    |> Enum.with_index(first)
    |> Enum.map(fn {child, pos} -> act_element(child, pos) end)
  end

  # --- Speech ---

  defp speech(attrs, children, pos) do
    {speaker_label, notes} = text_and_notes(find_child(children, "speaker"))

    %{
      type: "speech",
      position: pos,
      speaker_label: speaker_label,
      who: who(attr_value(attrs, "who")),
      notes: notes,
      elements: speech_content(children)
    }
  end

  # A speech's line groups, lines, stage directions and paragraphs.
  defp speech_content(children) do
    children
    |> Enum.filter(&match?({name, _, _} when name in ~w(lg l stage p), &1))
    |> Enum.with_index()
    |> Enum.map(fn
      {{"lg", attrs, lg_children}, pos} -> line_group(attrs, lg_children, pos)
      {{"l", _, _} = line, pos} -> verse_line(line, pos)
      {{"stage", _, _} = stage, pos} -> stage_direction(stage, pos)
      {{"p", _, _} = para, pos} -> prose(para, pos)
    end)
  end

  # who can be "#ALFONSO" (single) or "#ALB #COR" (multi-character, space-separated)
  defp who(nil), do: []

  defp who(who) do
    who
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&(&1 |> String.replace("#", "") |> String.trim()))
  end

  # --- Line group ---

  defp line_group(attrs, children, pos) do
    %{
      type: "line_group",
      position: pos,
      verse_type: attr_value(attrs, "type"),
      part: attr_value(attrs, "part"),
      notes: [],
      elements:
        children
        |> Enum.filter(&match?({name, _, _} when name in ~w(l stage), &1))
        |> Enum.with_index()
        |> Enum.map(fn
          {{"l", _, _} = line, line_pos} -> verse_line(line, line_pos)
          {stage, stage_pos} -> stage_direction(stage, stage_pos)
        end)
    }
  end

  # --- Verse line ---

  defp verse_line({_name, attrs, children} = line, pos) do
    is_aside = aside_delivery?(children)
    {content, notes} = line |> verse_line_content(is_aside) |> take_notes(line)

    %{
      type: "verse_line",
      position: pos,
      content: content,
      line_number: parse_int(attr_value(attrs, "n")),
      line_id: attr_value(attrs, "xml:id") || attr_value(attrs, "id"),
      part: attr_value(attrs, "part"),
      rend: attr_value(attrs, "rend"),
      is_aside: is_aside,
      notes: notes,
      elements: []
    }
  end

  # verbatim: lines 1445-1484 (aside_delivery?/1, verse_line_content/2, aside_seg?/1)

  # --- Stage direction, trailer, prose ---

  defp stage_direction({_name, attrs, _children} = stage, pos) do
    {content, notes} = text_and_notes(stage)

    %{
      type: "stage_direction",
      position: pos,
      content: content,
      stage_type: attr_value(attrs, "type"),
      notes: notes,
      elements: []
    }
  end

  defp trailer(trailer, pos) do
    {content, notes} = text_and_notes(trailer)
    %{type: "trailer", position: pos, content: content, notes: notes, elements: []}
  end

  defp prose({_name, _attrs, children} = para, pos) do
    is_aside = aside_in_children?(children)
    marked = if is_aside, do: aside_content(children), else: text_content(para, :mark)
    {content, notes} = take_notes(marked, para)

    %{
      type: "prose",
      position: pos,
      content: content,
      is_aside: is_aside,
      notes: notes,
      elements: []
    }
  end

  # verbatim: lines 1543-1554 (aside_in_children?/1, aside_content/1)

  # verbatim: lines 1575-1730 ("# --- XML helpers ---" through nested_notes/1), with
  # take_notes/2's comment and ending changed as Step 3a says

  # An element of the play text read with its notes taken out: `{text, [note]}`, or
  # `{nil, []}` for no element.
  defp text_and_notes(nil), do: {nil, []}
  defp text_and_notes(element), do: element |> text_content(:mark) |> take_notes(element)

  # A note's own fields at `offset`, as a list: empty when the note has no text, since
  # there is nothing to show (the empty notes of the EMOTHE0010 test file).
  defp parse_note({"note", attrs, children}, offset) do
    body =
      case find_children(children, "p") do
        [] ->
          text_content({"note", attrs, Enum.reject(children, &match?({"term", _, _}, &1))})

        paragraphs ->
          paragraphs
          |> Enum.map(&text_content/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")
      end

    term = safe_text(find_child(children, "term"))

    if body == "" do
      []
    else
      [
        %{
          offset: offset,
          n: attr_value(attrs, "n"),
          type: attr_value(attrs, "type"),
          term: if(term in [nil, ""], do: nil, else: term),
          body: body
        }
      ]
    end
  end

  # verbatim: lines 1783-1864 (safe_text/1 through format_title_segment/2)
end
```

- [ ] **Step 3a: Change `take_notes/2`'s ending in the copied block**

In the copy of `take_notes/2` (it sits inside lines 1575-1730), replace the first two lines of its comment

```elixir
  # Takes the note marks out of `marked`, text `element` was read into with :mark.
  # Returns the text and `[{offset, note}]`, the offset counting graphemes of the text
```

with

```elixir
  # Takes the note marks out of `marked`, text `element` was read into with :mark.
  # Returns the text and its notes (parse_note/2), each offset counting graphemes of the text
```

and its last expression

```elixir
    {text,
     found |> Enum.reverse() |> Enum.map(fn {offset, note} -> {min(offset, last), note} end)}
```

with

```elixir
    {text,
     found
     |> Enum.reverse()
     |> Enum.flat_map(fn {offset, note} -> parse_note(note, min(offset, last)) end)}
```

Also, in that comment, after "is dropped with it." add " So is a note with no text."

- [ ] **Step 4: Run the new test**

Run: `mix test test/playcode/import/tei_parser_test.exs`
Expected: PASS. (Compile warnings about unused private functions in `tei_import.ex` are expected until Step 5.)

- [ ] **Step 5: Turn `TeiImport` into the writer**

Replace `lib/playcode/import/tei_import.ex` with the following. Each `# verbatim: lines X-Y` comment is replaced by those lines of the file as it stands before this step (Task 1's line numbers; read them from `git show HEAD:lib/playcode/import/tei_import.ex`); all reading code goes, since it now lives in `TeiParser`.

```elixir
defmodule Playcode.Import.TeiImport do
  @moduledoc """
  Imports a TEI-XML file: `Playcode.Import.TeiParser` reads it, this module writes what
  it read, in one transaction.

  A re-import updates the play with that code in place. It replaces the play's whole
  text and the editors, sources, editorial notes, witnesses and place links the importer
  created itself (`origin: "tei"`); everything a researcher typed is kept, and so are the
  columns the platform owns. `preview_import/1` reports that before anything is written.
  """

  import Ecto.Query

  alias Playcode.Catalogue
  alias Playcode.Catalogue.{Play, PlayEditor, PlaySource, PlayEditorialNote}
  alias Playcode.Import.TeiParser
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Character, Division, Element}
  alias Playcode.Places
  alias Playcode.Repo
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness

  require Logger

  # verbatim: lines 22-37 (the @platform_owned comment and list)

  @doc """
  Imports a TEI-XML file from the given path into the database.
  Returns {:ok, play} or {:error, reason}.
  """
  def import_file(path) do
    Logger.info("Importing TEI file: #{path}")

    case TeiParser.parse_file(path) do
      {:ok, tei} ->
        Repo.transaction(fn -> write(tei) end)

      {:error, reason} ->
        Logger.error("Import failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # verbatim: lines 88-95 (preview_import/1's @doc)
  def preview_import(path) do
    with {:ok, tei} <- TeiParser.parse_file(path), do: {:ok, preview(tei.play)}
  end

  defp preview(%{code: code, title: title}) do
    existing = Repo.get_by(Play, code: code)

    %{
      code: code,
      title: title,
      existing: existing,
      archived: not is_nil(existing) and not is_nil(existing.deleted_at),
      replaces: replaced_counts(existing),
      preserves: preserved_counts(existing),
      preserves_fields: preserved_fields(existing)
    }
  end

  # verbatim: lines 127-194 (mixed_ownership_total/1 with its @doc, replaced_counts/1,
  # preserved_counts/1, preserved_fields/1, count_rows/2, count_rows/3)

  # --- Writing ---

  # Everything the file supplies, in one transaction: the play, its header records, the
  # cast and front matter, then the text.
  defp write(tei) do
    play = write_play(tei.play)

    Enum.each(tei.editors, &Catalogue.create_play_editor(tei_row(&1, play)))
    Enum.each(tei.sources, &Catalogue.create_play_source(tei_row(&1, play)))
    write_witnesses(tei.witnesses, play)
    Enum.each(tei.places, &write_place(&1, nil))
    write_settings(tei.settings, play)

    Enum.each(
      tei.characters,
      &PlayContent.create_character_unless_exists(Map.put(&1, :play_id, play.id))
    )

    Enum.each(tei.editorial_notes, &Catalogue.create_play_editorial_note(tei_row(&1, play)))

    cast = Map.new(PlayContent.list_characters(play.id), &{&1.xml_id, &1.id})
    Enum.each(tei.divisions, &write_division(&1, play, nil, cast))

    # Recompute verse_count from actual verse_line elements (the TEI header
    # <extent> value is often inaccurate or includes non-verse lines), and return
    # the play as that left it rather than the stale struct from before.
    {:ok, play} = Catalogue.update_verse_count(play.id)
    play
  end

  # Every editor, source, note and witness the importer creates is stamped
  # `origin: "tei"`, so a re-import can replace its own rows and leave hand-entered ones
  # alone. Rows created anywhere else default to "manual".
  defp tei_row(attrs, play), do: Map.merge(attrs, %{play_id: play.id, origin: "tei"})

  defp write_play(attrs) do
    case Repo.get_by(Play, code: attrs.code) do
      %Play{} = existing_play ->
        reset_tei_content(existing_play)

        case Catalogue.update_play(existing_play, Map.drop(attrs, @platform_owned)) do
          {:ok, play} ->
            # An import of an archived play brings it back — the file is the reason it
            # is wanted again.
            play |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update!()

          {:error, changeset} ->
            Repo.rollback(changeset)
        end

      nil ->
        case Catalogue.create_play(attrs) do
          {:ok, play} -> play
          {:error, changeset} -> Repo.rollback(changeset)
        end
    end
  end

  # verbatim: lines 278-294 (the comment above reset_tei_content/1, and reset_tei_content/1)

  # --- Witnesses ---

  # A siglum the play already has — a witness typed by hand, a modern edition in its
  # bibliography, or one earlier in the same file — is left out (Witnesses.taken_sigla/1,
  # after reset_tei_content/1 removed the file's own). So is a witness printing the same
  # line as one the play kept: most FileMaker witnesses have no siglum, and the play's own
  # export lists them. A witness with nothing to print fails its changeset and is left
  # out too.
  defp write_witnesses([], _play), do: :ok

  defp write_witnesses(witnesses, play) do
    kept = play.id |> Witnesses.list_for_play() |> MapSet.new(&Witnesses.plain/1)

    Enum.reduce(witnesses, Witnesses.taken_sigla(play.id), fn witness, taken ->
      attrs = tei_row(witness, play)

      if attrs.siglum in taken or Witnesses.plain(struct(Witness, attrs)) in kept do
        taken
      else
        _ = Witnesses.create_witness(attrs)
        if attrs.siglum, do: MapSet.put(taken, attrs.siglum), else: taken
      end
    end)

    :ok
  end

  # --- Places ---

  # A place is found by its slug or created, then the places nested in it. The gazetteer
  # is corpus-global authority data: a place already there is used, never changed.
  defp write_place(%{attrs: attrs, slug_declared: slug_declared, places: places}, parent_id) do
    slug = attrs["slug"]

    case Places.find_or_create_by_slug(Map.put(attrs, "parent_place_id", parent_id)) do
      {:ok, place, outcome} ->
        cond do
          outcome != :existing ->
            :ok

          # No xml:id means the slug was derived from the name, so two distinct
          # referents that happen to share a name silently become one row. Our own
          # exporter always writes xml:id; a hand-authored file may not.
          not slug_declared ->
            Logger.warning(
              "TEI import: <place> without xml:id resolved to existing place #{inspect(slug)} " <>
                "by name — if these are different places, give each an xml:id"
            )

          true ->
            Logger.info("TEI import: place #{slug} already exists, left unchanged")
        end

        # Nested <place> elements are this place's children.
        Enum.each(places, &write_place(&1, place.id))

      {:error, changeset} ->
        Logger.warning("TEI import: could not create place #{slug}: #{inspect(changeset.errors)}")
    end
  end

  defp write_settings(settings, play) do
    Enum.each(settings, fn setting ->
      case Repo.get_by(Places.Place, slug: setting.slug) do
        nil ->
          Logger.warning("TEI import: setting references unknown place #{inspect(setting.slug)}")

        place ->
          link_attrs = %{
            "role" => setting.role,
            "position" => setting.position,
            "note" => setting.note,
            "origin" => "tei"
          }

          # A hand-linked place (origin "manual") surviving from before this file ever
          # mentioned it collides with the (play_id, place_id) unique index on a blind
          # insert — reset_tei_content only clears this play's own "tei" links, on
          # purpose. Leave the curated row alone: writing "tei" over its origin would
          # hand it to reset_tei_content, and the next re-import would delete it along
          # with its note. Only a link this importer already owns gets refreshed.
          case Repo.get_by(Places.PlayPlace, play_id: play.id, place_id: place.id) do
            nil ->
              Places.link_place(play.id, place.id, link_attrs)

            %{origin: "tei"} = existing ->
              Places.update_play_place(existing, link_attrs)

            existing ->
              Logger.info(
                "TEI import: <setting> names #{inspect(setting.slug)}, already linked with " <>
                  "origin #{inspect(existing.origin)} — left untouched"
              )
          end
      end
    end)
  end

  # --- Text ---

  # A division, the notes in its heading, its elements, then its subdivisions. Positions
  # come from the file; parents from where the row sits in the tree.
  defp write_division(division, play, parent_id, cast) do
    attrs =
      division
      |> Map.drop([:notes, :elements, :divisions])
      |> Map.merge(%{play_id: play.id, parent_id: parent_id})

    row =
      case PlayContent.create_division(attrs) do
        {:ok, row} -> row
        {:error, cs} -> Repo.rollback({:division_create_failed, cs})
      end

    write_notes(division.notes, %{division_id: row.id}, play)
    Enum.each(division.elements, &write_element(&1, play, row.id, nil, cast))
    Enum.each(division.divisions, &write_division(&1, play, row.id, cast))
  end

  defp write_element(element, play, division_id, parent_id, cast) do
    attrs =
      element
      |> Map.drop([:who, :notes, :elements])
      |> Map.merge(%{play_id: play.id, division_id: division_id, parent_id: parent_id})

    row =
      case PlayContent.create_element(attrs) do
        {:ok, row} ->
          row

        # The type is one of the parser's six, never a value from the file.
        {:error, cs} ->
          Repo.rollback({:element_create_failed, String.to_atom(element.type), cs})
      end

    write_notes(element.notes, %{element_id: row.id}, play)

    case character_ids(element, cast) do
      [] -> :ok
      ids -> PlayContent.set_element_characters(row.id, ids)
    end

    Enum.each(element.elements, &write_element(&1, play, division_id, row.id, cast))
  end

  # The characters a speech's `who` names. A ref to no one in the cast is dropped, and a
  # repeated one ("#horatio #barnardo #marcellus #barnardo") counted once, which the
  # element_characters unique index requires.
  defp character_ids(%{who: who}, cast),
    do: who |> Enum.map(&cast[&1]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

  defp character_ids(_element, _cast), do: []

  # Notes in document order: `create_note/1` puts each after the notes already at its
  # offset.
  defp write_notes(notes, anchor, play) do
    Enum.each(notes, fn note ->
      case PlayContent.create_note(note |> Map.merge(anchor) |> Map.put(:play_id, play.id)) do
        {:ok, _note} -> :ok
        {:error, cs} -> Repo.rollback({:note_create_failed, cs})
      end
    end)
  end
end
```

Note on the log: `import_file/1` now logs "Import failed" for every file the reader refuses, a missing `teiHeader` included (before, that one rolled back silently). The only other log difference: a `<note>` without `type="place"` under a `<place>` nested in a place the gazetteer refused is now logged too, because the reader reads every place before anything is written. Neither is asserted anywhere; say both in the report.

- [ ] **Step 6: Compile and run the importer's tests**

```bash
mix compile --warnings-as-errors
mix test test/playcode/import test/playcode/tei_roundtrip_test.exs
```

Expected: no warnings (an unused private function means a block was copied into the wrong module, or a reading function was left in `TeiImport`); all tests PASS. On a failure, read it before changing anything: the old code is in `git show HEAD:lib/playcode/import/tei_import.ex`, and the difference is a copying slip, not a test to adjust.

- [ ] **Step 7: Prove the purity test bites**

Add `_ = Playcode.Repo.get_by(Play, code: "x")` as the first line of `TeiParser.parse_file/1`.
Run: `mix test test/playcode/import/tei_parser_test.exs`
Expected: FAIL with `DBConnection.OwnershipError` ("cannot find ownership process"). Remove the line; run again: PASS.

- [ ] **Step 8: Refactor while green**

- Read `tei_parser.ex` top to bottom: section headings in reading order, no comment that still speaks of creating rows (`grep -n "creat\|Repo\|insert" lib/playcode/import/tei_parser.ex` should find only `Places.slugify`-style names, nothing that writes).
- Read `tei_import.ex`: no reading code left (`grep -n "find_child\|attr_value\|text_content" lib/playcode/import/tei_import.ex` finds nothing).
- Both moduledocs describe what the module now does.
- Run `mix test test/playcode/import test/playcode/tei_roundtrip_test.exs` after each change.

- [ ] **Step 9: The whole suite, slow included**

```bash
mix format
mix compile --warnings-as-errors
mix test 2>&1 | tail -5
mix test --include slow 2>&1 | tail -5
```

Expected: `0 failures` both times; the default run has exactly one more test than after Task 2 (the new reader test).

- [ ] **Step 10: The golden master again, and the diff**

```bash
export SCRATCH=/tmp/claude-1000/-home-bogdan-Projects-playcode/f84b3c39-8555-4e4c-906d-0e02add3e3ae/scratchpad
MIX_ENV=test MIX_TEST_PARTITION=_golden mix ecto.drop
MIX_ENV=test MIX_TEST_PARTITION=_golden mix ecto.create
MIX_ENV=test MIX_TEST_PARTITION=_golden mix ecto.migrate
MIX_ENV=test MIX_TEST_PARTITION=_golden mix run $SCRATCH/golden_dump.exs $SCRATCH/golden/after 2>&1 \
  | sed -E 's/^[0-9:. ]+//' > $SCRATCH/golden/after.log
diff -r $SCRATCH/golden/before $SCRATCH/golden/after && echo IDENTICAL
diff $SCRATCH/golden/before.log $SCRATCH/golden/after.log
```

Expected: `IDENTICAL`. The log diff may show only the two differences Step 5's note names. Any other difference is a behaviour change: find the play and table in the diff, compare the old function (`git show HEAD:lib/playcode/import/tei_import.ex`) with its replacement, fix the code, and run this step again. Then drop the scratch database: `MIX_ENV=test MIX_TEST_PARTITION=_golden mix ecto.drop`.

- [ ] **Step 11: Check the commit touches no existing test**

Run: `git status --short`
Expected: `M lib/playcode/import/tei_import.ex`, `?? lib/playcode/import/tei_parser.ex`, `?? test/playcode/import/tei_parser_test.exs`, and nothing else.

- [ ] **Step 12: Commit the split**

```bash
git add lib/playcode/import/tei_parser.ex lib/playcode/import/tei_import.ex test/playcode/import/tei_parser_test.exs
git commit -m "refactor(import): TeiParser reads a TEI file without the database, TeiImport writes it

TeiParser.parse_file/1 turns a file into plain data (the play, its header records,
cast, front matter and the division and element tree, with positions, who refs and
note offsets); TeiImport writes that in one transaction, and the preview reuses the
same parse. The steps that depend on database state stay in the writer: the upsert by
code, character suffixing, the witness skip rules and the gazetteer.

No existing test changed. The new reader test runs without a sandbox checkout, so a
database call in the reader fails it (seen: DBConnection.OwnershipError). The golden
master, every corpus play's rows and TEI export after a first import and a forced
re-import, is identical before and after.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016rfo2oSmWLTfvMmhBx4FKF"
```

- [ ] **Step 13: Docs**

Measure: `wc -l lib/playcode/import/tei_parser.ex lib/playcode/import/tei_import.ex`.

1. `docs/backlog.md`: delete the `## Code health` heading and its one item ("Separate parsing from writing in `TeiParser`").
2. `docs/history.md`: at the end of `## Found by the Groxio audit (2026-10-08)`, add (with the measured counts):
   ```markdown
   - [x] **Reading a TEI file was mixed with writing it** - the importer created rows while it walked the XML (1,865 lines, about 50 `Repo`/context calls), so no part of an import ran without a database and the preview read the header a second way. Now `Import.TeiParser.parse_file/1` (N lines) turns a file into plain data, with positions, `who` refs and note offsets already counted, and `Import.TeiImport` (M lines) writes it in one transaction; the preview reuses the parse. The writer keeps what depends on the database: the upsert by code, the character suffix, the witness skip rules, the gazetteer. Proved by a golden master: every corpus play's rows and TEI export, after a first import and a forced re-import, identical before and after; `tei_parser_test.exs` runs with no sandbox checkout, so a database call in the reader fails it. Spec and plan: `docs/superpowers/specs/2026-10-10-tei-read-write-split-design.md`, `docs/superpowers/plans/2026-10-10-tei-read-write-split.md`
   ```
3. `docs/architecture.md`: replace the line `│   │   ├── tei_import.ex             # TEI-XML importer (handles UTF-16 files)` with
   ```
   │   │   ├── tei_parser.ex             # Reads a TEI-XML file into plain data, no database (handles UTF-16 files)
   │   │   ├── tei_import.ex             # Writes what TeiParser read, in one transaction; the import preview
   ```

```bash
git add docs/backlog.md docs/history.md docs/architecture.md
git commit -m "docs: the TEI read/write split, from the backlog to history

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_016rfo2oSmWLTfvMmhBx4FKF"
```
