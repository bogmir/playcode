# FileMaker's Plays Without a Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The works FileMaker holds with no web edition and that Playcode does not hold (121 on today's export) become draft plays, with everything today's export says about them, and the existing FileMaker imports then fill their witnesses, bibliography, places and performances.

**Architecture:** A new reader in `Playcode.Import.Filemaker` returns each T01 record's creation fields. `Playcode.Import.FilemakerPlays` has a pure `plan/2` (records and held plays in, plays to create and a report out) and an `apply_plan/1` that creates them through `Catalogue.create_play/1`. A mix task and a `Playcode.Release` twin run it, dry run first. Nothing is stored that the TEI file does not already carry.

**Tech Stack:** Elixir, Jason (NDJSON), Ecto, Mix tasks, ExUnit.

**Spec:** `docs/superpowers/specs/2026-11-17-plays-without-text-and-record-search-design.md`, section 7.6 (the columns, the selection, what is missing) and the FileMaker half of section 5. Read both before Task 1. `docs/development.md`, *FileMaker*, says how the other imports run and what a re-run keeps.

**Needs:** plan `2026-11-17-plays-without-text.md` merged (a play created with no text must be a play without a text).

## Global Constraints

- Work on branch `feature/filemaker-plays-without-text` in a git worktree of its own. Check the branch before every commit.
- Every task is red, green, refactor, then commit. Prove a test bites with `bin/bites` when it passes at once.
- The rules are tested through `FilemakerPlays.plan/2`, the writes through `Mix.Task.rerun/2` (CLAUDE.md, *Testing through the outermost API*); read back through `Catalogue`, never `Repo`.
- Every import has a dry run that writes nothing, and a second run that changes nothing.
- A TEI file names no FileMaker identifier, and Playcode stores none for a play: the work number (`_IdObraEmothe`) is printed in the report and nowhere else.
- The task never sets `relationship_type`, `parent_play_id`, `is_complete`, `original_title`, or the composition years.
- The real export (`doc/w3emothe_T01_tituloEM.ndjson`, git-ignored) is read only by hand in Task 4; tests use fixtures under `test/fixtures/filemaker/`.
- Plain `mix test PATH`; `mix format`; no `Co-Authored-By` trailer.

## Review Focus

1. **A record whose code Playcode holds with a readable tail** (`EMOTHE0195_Macbeth` for FileMaker's 195), or holds archived: skipped, by `Play.short_code/1`, archived plays included. Test in Task 2.
2. **A record with no language, an unknown language number, or no number at all**: skipped and reported with its title; the run goes on. Test in Task 2.
3. **An author with no comma, with two commas, or none** ("Molière"; "Lope de Vega y Carpio, Félix"; "Calderón de la Barca, Pedro, y otros"): as it is; turned at the first comma; none. Test in Task 2.
4. **A second run, and a run after a curator archived one of the new plays**: creates nothing. Test in Task 3.
5. **A title or author with HTML or stray spaces from FileMaker** (`pub_Titulo` holds plain text today, the rendered fields hold tags): trimmed, tags stripped as `Filemaker` strips the notes'. Test in Task 1.

---

### Task 1: Read each record's creation fields

**Files:**
- Modify: `lib/playcode/import/filemaker.ex` (beside `load_versions/1` at line 74 and `build_version/2` at 120)
- Create: `test/fixtures/filemaker/plays_sample.ndjson`
- Test: `test/playcode/import/filemaker_test.exs`

**Interfaces:**
- Produces: `Playcode.Import.Filemaker.load_records(path \\ default_path()) :: {:ok, [record]} | {:error, reason}`, the T01 records in file order, each

```elixir
%{
  code: "EMOTHE0596" | nil,          # as load_versions/1 works it out (the private version_code/1)
  title: String.t() | nil,           # pub_Titulo
  title_sort: String.t() | nil,      # pub_TituloOrden
  author_sort: String.t() | nil,     # pub_Autor
  language: "es" | "fr" | "en" | "it" | "pt" | nil,   # bus_idioma 1, 2, 3, 4, 5
  web_edition: true | false | nil,   # bus_edicionWeb "1", "0", ""
  work: String.t() | nil,            # _IdObraEmothe
  translator: String.t() | nil,      # bus_tradTraductor, its lines joined with "; "
  historical_time: String.t() | nil, historical_time_note: String.t() | nil, composition_date_note: String.t() | nil
}
```

  Errors as `load_versions/1` gives them, `{:malformed_record, record_id}` among them. `load_versions/1` is unchanged.

- [ ] **Step 1: Write the fixture and the failing tests.** `plays_sample.ndjson`: the `_meta` line for layout `T01_tituloEM`, six records, the `_end` line, in the shape of `versions_sample.ndjson`:

  | `_IdTituloEmothe` | `pub_Titulo` | `pub_TituloOrden` | `pub_Autor` | `bus_idioma` | `bus_edicionWeb` | `_IdObraEmothe` | other |
  |---|---|---|---|---|---|---|---|
  | 596 | `  L’abuseur de Séville ` | `abuseur de Séville, L’` | `Molina, Tirso de` | 2 | 0 | 84 | `bus_tradTraductor` "Jacquot, Jean\nDupont, Marie"; `bus_tiemHistorico` "8"; `pub_TiemHistorico` and `pub_datacion` as one record of `versions_sample.ndjson` has them |
  | 439 | `El Adonis` | `Adonis, El` | `Molière` | 1 | 0 | 192 | |
  | 195 | `Macbeth` | `Macbeth` | `Shakespeare, William` | 2 | 0 | 61 | |
  | 700 | `Sin idioma` | `Sin idioma` | `Anónimo` | `` | 0 | 300 | |
  | 701 | `Con edición` | `Con edición` | `Vega, Lope de` | 1 | 1 | 301 | `pub_edicionWeb` an `<a href='…/textosEMOTHE/EMOTHE0701_ConEdicion.php'>` |
  | 702 | `Idioma raro` | `Idioma raro` | `` | 9 | 0 | 302 | |

```elixir
describe "load_records/1" do
  @plays "test/fixtures/filemaker/plays_sample.ndjson"

  test "reads each record's title, author, language and flags" do
    assert {:ok, [first, adonis | _] = records} = Filemaker.load_records(@plays)
    assert length(records) == 6
    assert %{code: "EMOTHE0596", title: "L’abuseur de Séville", title_sort: "abuseur de Séville, L’",
             author_sort: "Molina, Tirso de", language: "fr", web_edition: false, work: "84",
             translator: "Jacquot, Jean; Dupont, Marie", historical_time: "siglo_xvii"} = first
    assert is_binary(first.composition_date_note)
    assert %{code: "EMOTHE0439", language: "es", translator: nil, historical_time: nil} = adonis
  end

  test "a language it does not know, or none, is nil; a web edition is told from none" do
    {:ok, records} = Filemaker.load_records(@plays)
    by = Map.new(records, &{&1.code, &1})
    assert by["EMOTHE0700"].language == nil
    assert by["EMOTHE0702"].language == nil
    assert by["EMOTHE0702"].author_sort == nil
    assert by["EMOTHE0701"].web_edition == true
  end

  test "a malformed record refuses the whole file" do
    assert {:error, {:malformed_record, _}} = Filemaker.load_records("test/fixtures/filemaker/malformed_version.ndjson")
  end
end
```

- [ ] **Step 2: Run** `mix test test/playcode/import/filemaker_test.exs` — expected: FAIL, `Filemaker.load_records/1 is undefined`.
- [ ] **Step 3: Implement** with the file's own helpers (`read_records/2`, `field/2`, `version_code/1`, `historical_time/1`, `historical_time_note/1`, `composition_date_note/1`, `strip_tags/1`). The language map is a module attribute with the comment "checked against 283 held plays, 2026-11-17".
- [ ] **Step 4: Run** — expected: PASS.
- [ ] **Step 5: Refactor while green.** `load_versions/1` and `load_records/1` share the line reader; neither builds the other's map.
- [ ] **Step 6: Commit** — `feat: read each FileMaker record's title, author, language and web-edition flag`

---

### Task 2: Which plays to create

**Files:**
- Create: `lib/playcode/import/filemaker_plays.ex`
- Test: `test/playcode/import/filemaker_plays_test.exs` (new, `use Playcode.DataCase, async: true`)

**Interfaces:**
- Consumes: `Filemaker.load_records/1` (Task 1); `Catalogue.list_plays(include_deleted: true)`; `Play.short_code/1`.
- Produces:

```elixir
FilemakerPlays.plan(records :: [record], plays :: [%Play{}]) :: %{
  create: [%{attrs: map(), relatives: [String.t()], translator: String.t() | nil}],   # in record order
  held: non_neg_integer(),              # no web edition, code already in Playcode
  skipped: [%{title: String.t() | nil, code: String.t() | nil, reason: :no_code | :no_language | :no_title}]
}
FilemakerPlays.author_name(author_sort :: String.t() | nil) :: String.t() | nil
```

  `attrs` is what `Catalogue.create_play/1` takes: `"code"`, `"title"`, `"title_sort"`, `"author_name"`, `"author_sort"`, `"language"`, `"historical_time"`, `"historical_time_note"`, `"composition_date_note"`, nil values left out. No `"auto_form"`: after plan 1 a play created with none has no text. `relatives` are the full codes of the held plays (not archived) whose FileMaker record shares the record's `work`, sorted. A record with `web_edition` true or nil is not looked at.

- [ ] **Step 1: Write the failing tests.**

```elixir
@plays "test/fixtures/filemaker/plays_sample.ndjson"
defp records, do: @plays |> Filemaker.load_records() |> elem(1)

test "a record with no web edition that Playcode does not hold becomes a play" do
  plan = FilemakerPlays.plan(records(), [])
  assert [abuseur, adonis, macbeth] = plan.create
  assert abuseur.attrs == %{"code" => "EMOTHE0596", "title" => "L’abuseur de Séville", "title_sort" => "abuseur de Séville, L’",
           "author_sort" => "Molina, Tirso de", "author_name" => "Tirso de Molina", "language" => "fr",
           "historical_time" => "siglo_xvii", "historical_time_note" => abuseur.attrs["historical_time_note"],
           "composition_date_note" => abuseur.attrs["composition_date_note"]}
  assert abuseur.translator == "Jacquot, Jean; Dupont, Marie"
  assert adonis.attrs["author_name"] == "Molière"
  assert macbeth.attrs["code"] == "EMOTHE0195"
end

test "a code Playcode holds is left alone, whatever its tail, archived or not" do      # Review Focus 1
  held = play_fixture(%{"code" => "EMOTHE0195_Macbeth"})
  {:ok, archived} = Catalogue.delete_play(play_fixture(%{"code" => "EMOTHE0439"}))
  plan = FilemakerPlays.plan(records(), [held, archived])
  assert Enum.map(plan.create, & &1.attrs["code"]) == ["EMOTHE0596"]
  assert plan.held == 2
end

test "a record with no language, or one it does not know, is skipped and named" do     # Review Focus 2
  plan = FilemakerPlays.plan(records(), [])
  assert %{title: "Sin idioma", code: "EMOTHE0700", reason: :no_language} in plan.skipped
  assert %{title: "Idioma raro", code: "EMOTHE0702", reason: :no_language} in plan.skipped
  refute Enum.any?(plan.create ++ plan.skipped, &(&1[:code] == "EMOTHE0701" or &1[:attrs]["code"] == "EMOTHE0701"))
end

test "a new play's relatives are the held plays of its FileMaker work" do
  # record 195's work is 61; a record of the fixture for a held play with work 84 would name it for 596:
  # add a seventh fixture record (597, work 84, web edition 1) and hold EMOTHE0597_Abuseur
  held = play_fixture(%{"code" => "EMOTHE0597_Abuseur"})
  plan = FilemakerPlays.plan(records(), [held])
  assert hd(plan.create).relatives == ["EMOTHE0597_Abuseur"]
end

test "an author is turned at its first comma" do                                       # Review Focus 3
  assert FilemakerPlays.author_name("Molina, Tirso de") == "Tirso de Molina"
  assert FilemakerPlays.author_name("Lope de Vega y Carpio, Félix") == "Félix Lope de Vega y Carpio"
  assert FilemakerPlays.author_name("Calderón de la Barca, Pedro, y otros") == "Pedro, y otros Calderón de la Barca"
  assert FilemakerPlays.author_name("Molière") == "Molière"
  assert FilemakerPlays.author_name(nil) == nil
end
```

Add the seventh record to the fixture and raise Task 1's count to 7. `Catalogue.delete_play/1` is archiving (`deleted_at`). The third author line pins what the rule gives for two commas: it is a known ceiling, reported in Task 4, not corrected by guessing.

- [ ] **Step 2: Run** `mix test test/playcode/import/filemaker_plays_test.exs` — expected: FAIL, the module is undefined.
- [ ] **Step 3: Implement** `plan/2` and `author_name/1`. No database call inside `plan/2`.
- [ ] **Step 4: Run** — expected: PASS.
- [ ] **Step 5: Refactor while green.** Selection, attributes and report are three small functions; the `@moduledoc` states the selection rule and the two things the task never sets, with the spec's reason.
- [ ] **Step 6: Commit** — `feat: plan the plays FileMaker holds with no text`

---

### Task 3: Create them, from a mix task and on Fly

**Files:**
- Modify: `lib/playcode/import/filemaker_plays.ex` (`apply_plan/1`, `report/1`)
- Create: `lib/mix/tasks/playcode.import.filemaker.plays.ex`
- Modify: `lib/playcode/release.ex` (beside `import_witnesses/2` at line 78)
- Test: `test/mix/tasks_test.exs`, `test/playcode/release_test.exs`

**Interfaces:**
- Produces:
  - `FilemakerPlays.apply_plan(plan) :: {:ok, %{created: non_neg_integer()}}` — every play in one transaction, each through `Catalogue.create_play/1`, each logged with `ActivityLog.log!/1` (`action: "create"`, `resource_type: "play"`, `metadata: %{"source" => "filemaker_plays"}`), as `FilemakerSync.apply_plan/2` logs its updates. A changeset error rolls the whole run back and is returned as `{:error, {code, changeset}}`.
  - `FilemakerPlays.report(plan) :: [String.t()]` — one line per play to create (`"EMOTHE0596  L’abuseur de Séville  [fr]  Tirso de Molina"`, then indented `"    same work as: EMOTHE0597_Abuseur"` and `"    translator: Jacquot, Jean; Dupont, Marie"` when there are any), one per skipped record with its reason, and a last line `"N to create, N already held, N skipped"`.
  - `mix playcode.import.filemaker.plays [--dry-run] [--path FILE]`.
  - `Playcode.Release.import_filemaker_plays(path, opts \\ [])`, `dry_run: true` first, printing the same report.

- [ ] **Step 1: Write the failing tests** in `test/mix/tasks_test.exs`, a `describe "mix playcode.import.filemaker.plays"`:

```elixir
@plays "test/fixtures/filemaker/plays_sample.ndjson"
defp run(args), do: capture_io(fn -> Mix.Task.rerun("playcode.import.filemaker.plays", ["--path", @plays | args]) end)

test "the dry run lists what it would create and writes nothing" do
  out = run(["--dry-run"])
  assert out =~ "EMOTHE0596  L’abuseur de Séville  [fr]  Tirso de Molina"
  assert out =~ "translator: Jacquot, Jean; Dupont, Marie"
  assert out =~ "Sin idioma"
  assert out =~ "3 to create, 0 already held, 2 skipped"
  assert find("EMOTHE0596") == nil
end

test "it creates each as a draft without a text, with its historical time" do
  run([])
  play = find("EMOTHE0596")
  assert %{title: "L’abuseur de Séville", author_name: "Tirso de Molina", author_sort: "Molina, Tirso de",
           language: "fr", is_complete: false, historical_time: "siglo_xvii",
           relationship_type: nil, parent_play_id: nil, composition_date_from: nil} = play
  refute Play.has_text?(play)
  assert [%{action: "create", metadata: %{"source" => "filemaker_plays"}}] = log(play)
end

test "a second run creates nothing, nor does one after a new play was archived" do    # Review Focus 4
  run([])
  {:ok, _} = Catalogue.delete_play(find("EMOTHE0439"))
  assert run([]) =~ "0 to create, 3 already held, 2 skipped"
end

test "such a play's TEI file imports back to the same play" do
  run([])
  play = find("EMOTHE0596")
  xml = export_tei(play)
  assert Map.take(import_tei!(xml), [:id, :title, :author_name, :language, :historical_time]) ==
           Map.take(Catalogue.get_play_with_all!(play.id), [:id, :title, :author_name, :language, :historical_time])
end
```

`find/1` is a private helper: `Enum.find(Catalogue.list_plays(include_deleted: true), &(&1.code == code))` (`Catalogue.get_play_by_code!/2` raises). `log/1` reads the play's entries through `ActivityLog.list_entries/1`; look at its options and return shape first. The count of 3 assumes Task 2's seventh record is a web edition. In `release_test.exs`: `Release.import_filemaker_plays(@plays, dry_run: true)` prints "dry run, nothing written" and creates nothing; without the option it creates the three.

- [ ] **Step 2: Run** both files — expected: FAIL, the task `playcode.import.filemaker.plays` could not be found.
- [ ] **Step 3: Implement.** The mix task in the shape of `lib/mix/tasks/playcode.import.filemaker.ex` (`@switches [dry_run: :boolean, path: :string]`, `Mix.raise` on a file it cannot read). `Release.import_filemaker_plays/2` in the shape of `import_witnesses/2`, with its `@doc` saying how the file reaches the machine (`fly ssh sftp shell`, as the others say).
- [ ] **Step 4: Run** both files — expected: PASS.
- [ ] **Step 5: Refactor while green.** The task and the release function share `plan`, `report` and `apply_plan`; neither formats a line itself.
- [ ] **Step 6: Commit** — `feat: mix playcode.import.filemaker.plays creates FileMaker's plays without a text`

---

### Task 4: The other imports reach them; the real export; the documents

**Files:**
- Test: `test/mix/tasks_test.exs` (one test per existing import, beside its own describe)
- Modify: `docs/development.md` (*FileMaker*: the new task, the order), `docs/architecture.md` (file map), `CLAUDE.md` (*Commands*: the new row), `docs/production-reimport.md` only if a step there lists the imports
- Modify: `docs/stakeholder/preguntas.html` (*FileMaker tables we still need*: check the seven items of spec 7.6 are there), `docs/backlog.md`, `docs/history.md`

**Interfaces:**
- Consumes: the four existing tasks, `mix playcode.import.witnesses`, `.bibliography`, `.places`, `.performances`, and their fixtures under `test/fixtures/filemaker/ctce_dades/`, `witnesses/`, `places/`, `performances/`.

- [ ] **Step 1: Write one test per import**: in each import's describe in `tasks_test.exs`, create a play without a text whose code is one the fixture tables hold rows for (`play_without_text_fixture(%{"code" => "EMOTHE0…"})`, the number taken from that describe's existing setup), run the task as the describe's other tests do, and assert through the context's reader that the play gained the rows (a witness, a bibliography link, a place link, a performance).
- [ ] **Step 2: Run** them — expected: PASS, since each import plans over every held play by `Play.short_code/1` (`Witnesses.plan/2`'s `by_code`). Prove each bites with `bin/bites` (break the import's code match). If one fails as written, the import assumes a text: fix it there, with this test as its regression test.
- [ ] **Step 3: Run the real export, dry.** `mix playcode.import.filemaker.plays --dry-run | tail -40`. Expected on a database loaded from `doc/tei_corpus/`: `121 to create`, codes from EMOTHE0034 to EMOTHE0632. Read the list: note the authors `author_name/1` turned badly (two commas) and the plays skipped, and put both lists in the commit body and in the backlog item. A number other than 121 is not a failure of the code: say what the database held and why it differs.
- [ ] **Step 4: Run it for real on dev**, then the four imports in the spec's order, each `--dry-run` first: `mix playcode.import.witnesses`, `mix playcode.import.bibliography`, `mix playcode.import.places`, `mix playcode.import.performances`. Record in `docs/history.md` how many of the new plays gained witnesses, bibliography, places and performances. Open three of them at `/admin/plays` and one's TEI export.
- [ ] **Step 5: Documents.** `docs/development.md`: what the task reads, what a re-run keeps (everything: it only creates), the order with the other four. `CLAUDE.md`: the command's row. `docs/backlog.md`: a new item, "FileMaker's plays without a text: kind, original, years and characters", with the seven missing things of spec 7.6 and the two lists of Step 3; the item *Plays without a text* moves to `docs/history.md` if plan 1 has not moved it. `preguntas.html`: nothing to add if this session's edit is there.
- [ ] **Step 6: Run** `mix precommit` and `node --test test/js/*.test.mjs` — expected: 0 failures. Paste both summaries into the commit body.
- [ ] **Step 7: Refactor while green; commit** — `feat: FileMaker's plays without a text, filled by the existing imports`
- [ ] **Step 8:** Tell the owner the branch is ready to merge, and that production needs the export copied to the machine and `Playcode.Release.import_filemaker_plays/2` run by hand, dry run first, then the four `Release.import_*`. No pull request; merge and push only when told. Do not run anything on Fly.
