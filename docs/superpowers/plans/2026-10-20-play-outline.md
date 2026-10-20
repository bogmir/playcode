# The play's outline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One order per play for its paratexts, scene of the action, cast lists and divisions, the same in the admin, the TEI file, the import and every page; several cast lists, each with its own entries, wherever the editor or the file puts them.

**Architecture:** A cast list stays an `elenco` division; a new table `cast_list_entries` holds its lines, each naming a character or none. Top-level paratexts and divisions share one `position` sequence per play (an act's scenes and lists share the act's). `Playcode.Outline` sorts a play's top-level items and says where each goes in the file (`:front | :body | :back`); the export, the renderers and the API read that instead of `play_paratexts.back`, which goes. A character's `name`, `description` and `position` become copies of its first entry in outline order, kept in step by `PlayContent.sync_characters/1`, so the speaker pickers, statistics and API read them unchanged.

**Tech Stack:** Elixir 1.19 / Phoenix 1.8 / LiveView 1.1, Ecto + PostgreSQL triggers, Saxy, xml_builder.

**Spec:** `docs/superpowers/specs/2026-10-20-play-outline-design.md` — read it first; this plan argues from it and does not repeat its reasons.

## Global Constraints

- TDD, CLAUDE.md's loop: failing test, see it fail, smallest code, see it pass, **refactor while green** (Saša Jurić's clear code: names, no duplication, the helper the code already has, the surrounding idiom), then `mix test` (whole suite), `mix format`, `mix compile --warnings-as-errors`, commit.
- Test through the outermost API: the content editor with `live/2` and `render_hook/3`, the file as round trips (`roundtrip/1`, `xml_elements/3`, `xml_texts/3`, the new `text_order/1`), read back through `PlayContent`, `Catalogue` and `Outline`, never `Repo`.
- **Prove a new test bites** where it covers code that already works: break the line, watch red, restore, say so in the commit.
- An id from the browser is resolved with a getter scoped to the play (`PlayContent.get_division/2`, `get_entry/2`, `get_character/2`, `Catalogue.get_paratext/2`); nil → reload and `LiveHelpers.put_gone_flash/1`. A list of ids from a drag is filtered to the play's own rows.
- An icon-only control (a drag handle) gets an `aria-label`; `accessibility_test.exs` must stay green.
- New gettext strings: `mix gettext.extract --merge`, check every entry it marks fuzzy, give the Spanish: Add division → Añadir división; Add subdivision → Añadir subdivisión; Add paratext → Añadir paratexto; Add an existing character → Añadir un personaje existente; Group → Grupo; Names no character → Sin personaje; Drag to reorder → Arrastrar para reordenar; "%{names} speak in the play and are in no other cast list." → "%{names} hablan en la obra y no están en ningún otro elenco."; "Delete this cast list? %{count} characters in no other list go with it." → "¿Borrar este elenco? Se van con él %{count} personajes que no están en ningún otro."
- A TEI file names no database id: an entry's role carries the character's `xml_id` (`xml:id` or `corresp="#…"`), never a uuid.
- No new dependencies.
- Work on branch `play-outline`. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Before staging `docs/backlog.md` or `docs/stakeholder/*.html`, `git diff` them; edits that are not yours mean asking the owner first.

## Review Focus

1. **A cast list with no entries yet** (just added, or one the migration left empty) → the exported file still validates and the list comes back where it stood: written as its `div`/`div1`/`div2 type="elenco"` with its head and no `castList`. Test in Task 3.
2. **A play with no body division** (every act deleted, or dragged so nothing follows) → everything in `<front>`, nothing lost on the round trip. Test in Task 3.
3. **A re-import onto a play whose hand-added paratext stands between two acts** → it keeps its place: the file's items take the positions it leaves free. Test in Task 2.
4. **Deleting an act whose cast list holds a speaking character's only entry** → refused, naming them, exactly as deleting the list itself is; the speeches never point at an undeclared `who`. Test in Task 7.
5. **A drag or delete carrying another play's id, or a deleted row's** → nothing written, the tab reloads with the gone flash. Tests in Tasks 7 and 8.

---

### Task 1: Cast list entries: the table, the migration, the characters kept in step

**Files:**
- Create: `priv/repo/migrations/20261020120000_create_cast_list_entries.exs`, `lib/playcode/play_content/cast_list_entry.ex`, `test/playcode/cast_lists_test.exs`
- Modify: `lib/playcode/play_content.ex`, `lib/playcode/play_content/character.ex`, `lib/playcode/play_content/division.ex`, `lib/playcode/import/word_parser.ex:628-645`, `test/playcode/content_version_test.exs`, the Word import's test

**Interfaces:**
- Produces:

```elixir
# CastListEntry, table cast_list_entries: play_id, cast_list_id (play_divisions, on delete cascade),
#   character_id (characters, on delete cascade; nil = names no character), name (required),
#   description, group_heading, position (default 0), timestamps. Trigger: play_row_changed().
# Division: has_many :entries, CastListEntry, foreign_key: :cast_list_id, preload_order: [asc: :position]
# Character: has_many :entries
PlayContent.list_cast_lists(play_id) :: [Division.t()]
  # every elenco division in outline order (a top-level list by its position, a list in an act
  # at its act's position, then its own), entries preloaded by position with :character
PlayContent.get_cast_list(play_id, id) :: Division.t() | nil
PlayContent.get_entry(play_id, id) :: CastListEntry.t() | nil
PlayContent.create_entry(attrs) :: {:ok, CastListEntry.t()} | {:error, Ecto.Changeset.t()}
PlayContent.update_entry(entry, attrs) / change_entry(entry, attrs \\ %{})
PlayContent.sync_characters(play_id) :: :ok
  # each character's name, description and position from its first entry in outline order;
  # position = the index of that entry among all linked entries in outline order
PlayContent.create_character(attrs) :: {:ok, Character.t()} | {:error, Ecto.Changeset.t()}
  # also makes its entry (name, description, group_heading from attrs) in attrs.cast_list_id,
  # or in the play's first list, made when the play has none (type elenco, at a position one
  # less than the play's first top-level item, 0 in an empty play)
```

- [ ] **Step 1: Write the failing tests** in `test/playcode/cast_lists_test.exs` (DataCase):

```elixir
test "a character takes its name, description and place from its first entry in outline order" do
  # a list inside act 1 created first, the list before the acts second: outline order wins
  play = play_fixture()
  act = division!(play, %{type: "acto", number: 1, position: 1})
  inner = division!(play, %{type: "elenco", parent_id: act.id, position: 0})
  {:ok, ana} = PlayContent.create_character(%{play_id: play.id, xml_id: "ANA", name: "ANA, disfrazada", cast_list_id: inner.id})
  front = division!(play, %{type: "elenco", title: "PERSONAS", position: 0})
  {:ok, _} = PlayContent.create_entry(%{play_id: play.id, cast_list_id: front.id, character_id: ana.id, name: "ANA", description: "dama"})

  assert [%{name: "ANA", description: "dama"}] = PlayContent.list_characters(play.id)
  assert [["ANA"], ["ANA, disfrazada"]] =
           for(list <- PlayContent.list_cast_lists(play.id), do: Enum.map(list.entries, & &1.name))
end

test "a new character in a play with no cast list arrives in one made at the head of the outline"
  # create_character with no cast_list_id on a play holding one act at position 0:
  # assert [%{type: "elenco", position: -1, entries: [%{name: "BLAS"}]}] = list_cast_lists(play.id)
```

`division!/2` is the test's own one-liner over `PlayContent.create_division/1`. In `content_version_test.exs`, add `cast_list_entries` the way the test lists every table with a `play_id`. In the Word import's test, assert the import makes one list holding an entry for every character: `[list] = PlayContent.list_cast_lists(play.id)` and `length(list.entries) == length(PlayContent.list_characters(play.id))`.

- [ ] **Step 2: Run** `mix test test/playcode/cast_lists_test.exs test/playcode/content_version_test.exs` — Expected: FAIL, `list_cast_lists/1` undefined and the table check naming `cast_list_entries`.

- [ ] **Step 3: Write the migration.** Create the table, its indexes (`cast_list_id`, `character_id`, `play_id`) and the `play_row_changed()` trigger as `20261020100000_create_performances.exs` does. Then, in SQL, in this order:
  1. an `elenco` division for every play with characters and none (title NULL);
  2. one top-level sequence per play, in the order the export writes today, ranked once into a temporary table and applied to both tables:

```sql
CREATE TEMP TABLE outline_rank AS
SELECT id, kind, row_number() OVER (PARTITION BY play_id ORDER BY grp, position, id) - 1 AS pos
FROM (
  SELECT id, play_id, 'paratext' AS kind, position,
         CASE WHEN back THEN 4 WHEN kind = 'lugar_accion' THEN 2 ELSE 0 END AS grp
  FROM play_paratexts
  UNION ALL
  SELECT id, play_id, 'division', position, CASE WHEN type = 'elenco' THEN 1 ELSE 3 END
  FROM play_divisions WHERE parent_id IS NULL
) items;
```

  3. an entry per character in its play's first `elenco` division (lowest position), with the character's name, description and position.

  `down` drops the table; positions are not restored. Plays holding several lists today (0112, 0283, 0555, 0714) get every entry in the first: their files' re-import sorts them.

- [ ] **Step 4: Implement** the schema, the associations and the `PlayContent` functions above. Every write that touches an entry or a list's order calls `sync_characters/1` last. `update_character/2` writes `name` and `description` to the character's first entry, then syncs; `reorder_characters/2` sets the entries' positions in the given order, then syncs: the Characters tab keeps working until Task 8 replaces it. `create_character_unless_exists/1` makes the entry too when it makes the character. In the Word import, create the `elenco` division before the characters and pass its id; the front-matter paratext, the list and the acts take positions 0, 1, 2… (today the paratext and the list tie on 0).

- [ ] **Step 5: Run the tests** — Expected: PASS. Then `mix ecto.migrate` on the dev database and check, both expecting 0:

```sql
SELECT count(*) FROM characters c WHERE NOT EXISTS (SELECT 1 FROM cast_list_entries e WHERE e.character_id = c.id);
SELECT count(*) FROM (SELECT play_id, position FROM play_paratexts UNION ALL
  SELECT play_id, position FROM play_divisions WHERE parent_id IS NULL) t
  GROUP BY play_id, position HAVING count(*) > 1;
```

`mix ecto.rollback` then `mix ecto.migrate` once more, to prove `down`.

- [ ] **Step 6: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 7: Commit** — `feat: cast list entries, and a character kept in step with its first`

---

### Task 2: The import reads every item where its file has it

**Files:**
- Create: `lib/playcode/outline.ex`, `test/fixtures/outline.xml`
- Modify: `lib/playcode/import/tei_parser.ex` (`parse` result ~1150, `back_matter/2` ~1168, `front/1` ~1291, `cast_list/1` ~1378, `body/2` ~1410, `act_content/1`), `lib/playcode/import/tei_import.ex` (`write/1` ~215, `write_text/3`, `collect_division/5`), `test/playcode/import/tei_import_test.exs`

**Interfaces:**
- Consumes: Task 1's `CastListEntry`, `list_cast_lists/1`, `sync_characters/1`.
- Produces:

```elixir
Outline.items(paratexts, divisions) :: [Paratext.t() | Division.t()]
  # the top-level items (divisions with no parent) sorted by {position, id}
# Parser: a cast list is a division map %{type: "elenco", title, position, entries: [entry], …};
#   entry = %{name, description, group_heading, ref: {:id, xml_id} | {:corresp, xml_id} | nil,
#   position}; characters = one map per role with an xml:id, as today.
# One position counter through front, body and back in document order; an act's scenes and
#   lists share the act's child counter.
```

- [ ] **Step 1: Sweep the corpus** before relying on the rule that tells a paratext `div1` from a division:

```bash
for f in doc/tei_corpus/*.xml test/fixtures/tei_files/*.xml; do
  for q in "count(//*[local-name()='body']/*[local-name()='div1' and not(*[local-name()!='head' and local-name()!='p'])])" \
           "count(//*[local-name()='front']/*[local-name()='castList'])" \
           "count(//*[local-name()='div'][count(*[local-name()='castList'])>1])" \
           "count(//*[local-name()='castItem' and @ana='oculto']/*[local-name()='role' and not(@xml:id)])"; do
    n=$(xmllint --xpath "$q" "$f" 2>/dev/null); [ "$n" != "0" ] && echo "$f $q $n"
  done
done
```

Expected: no output. Any line means a file the rules below misread: stop and bring it to the owner.

- [ ] **Step 2: Write `test/fixtures/outline.xml`**, in its neighbours' encoding, written as Playcode writes a file (Task 3 compares it with its round trip), a play holding every row of the spec's table:
  - front: titlePage; `div type="dedicatoria"`; `set` (the scene, before the list, as *Egle*); `div type="elenco"` with head "PERSONAS" and a `castList` of: `role xml:id="ANA"` "ANA" + `roleDesc` "dama"; a `castGroup` headed "Criados" holding `role xml:id="BLAS"` and `role xml:id="CRISPÍN"`; `role` "Músicos" with no id; then `div type="head_title"` (question 32: after the list);
  - body: `div1 type="acto" n="1"` with a head, a bare `castList` (head "Personas del acto primero", `role corresp="#ANA"` "ANA, disfrazada" + `roleDesc` "de hombre"), `div2 type="escena"` 1 with a speech `who="#ANA"`, `div2 type="elenco"` (head + `castList` with `role xml:id="DIEGO"`), `div2 type="escena"` 2 with a speech `who="#DIEGO"`; `div1 type="elenco"` (head + `castList` with `role corresp="#BLAS"`); `div1 type="loa"` with only head and `p`; `div1 type="acto" n="2"` with a scene and a speech;
  - back: `div type="epilogo"` (head, `p`); `div type="elenco"` (head + `castList` with `role corresp="#CRISPÍN"`).

- [ ] **Step 3: Write the failing tests** in `tei_import_test.exs`, each importing the fixture through `TeiImport.import_file/1`:

```elixir
test "every cast list comes in where its file has it, each with its own entries" do
  # names per list, in outline order:
  assert [["ANA", "BLAS", "CRISPÍN", "Músicos"], ["ANA, disfrazada"], ["DIEGO"], ["BLAS"], ["CRISPÍN"]] = …
  # "Criados" is the group_heading of BLAS and CRISPÍN in the first list only; "Músicos" names no
  # character; the bare castList and the div2 are children of act 1 at 0 and 2 (scene 1 at 1);
  # four characters: ANA (description "dama"), BLAS, CRISPÍN, DIEGO
end

test "paratexts, the scene, lists and divisions take one order, the file's" do
  assert ~w(dedicatoria lugar_accion elenco head_title acto elenco loa acto epilogo elenco) =
           play.id |> outline_items() |> Enum.map(&(Map.get(&1, :kind) || &1.type))
end

test "a re-import leaves a hand-added paratext where it stood" do
  # import; Catalogue.create_paratext(%{play_id:, kind: "nota_edicion_digital", heading: "A mano",
  # origin: "manual", position: 6}) (the loa's number: it stood between the list and the loa
  # once the loa moved on); import again; the kinds read
  # …"acto", "elenco", "nota_edicion_digital", "loa", "acto"…
end

test "a role whose xml:id is already taken in the file is an entry for that character"
  # a small inline file with two lists, both declaring xml:id="ANA": one character, two entries
```

`outline_items/1` is the test's own helper: `Outline.items(Catalogue.list_paratexts(id), PlayContent.list_top_divisions(id))`.

- [ ] **Step 4: Run** `mix test test/playcode/import/tei_import_test.exs` — Expected: FAIL (one list's entries are missing, the loa is a division, the scene stands after the list).

- [ ] **Step 5: Implement the parser.**
  - Front, body and back are read child by child in document order onto one counter. Front: a `div` (an `elenco` one is a list), the `set`, a bare `castList` each take a position; the title page and the performances take none.
  - Body: a `div1 type="elenco"` is a list; a `div1` whose children are only `head` and `p` is a paratext of its type (through `kind/1`, so `circunstancia_accion` is the scene); any other `div1` a division, as today.
  - Inside an act, a bare `castList` and a `div2 type="elenco"` are lists on the scenes' child counter.
  - Back: an `elenco` div is a list. Paratexts read from `<back>` keep `back: true` until Task 6 removes the column.
  - A list's head is the div's `head`, or the `castList`'s own for a bare one; a `div`/`div1`/`div2 type="elenco"` with no `castList` is a list with no entries (Task 3 writes empty lists that way).
  - Entries come from `castItem`s in order, and from each `castGroup`'s items with its `head` as their `group_heading`. A role's `xml:id` (or `id`) is `{:id, xml_id}` the first time the file names it and `{:corresp, xml_id}` after; a `corresp="#X"` is `{:corresp, "X"}`; a role with neither is `ref: nil`. The name no longer stands in for a missing id.

- [ ] **Step 6: Implement the import.** Characters are inserted with `insert_rows/3` like the text's rows (one per `{:id, _}` role, `Character.changeset/2`), replacing the `create_character_unless_exists/1` call. `collect_division/5` collects a list's entries as `CastListEntry` rows, `character_id` from the xml_id map (nil for `ref: nil`, and for a `corresp` naming no role, which the file's own validation would refuse). The top-level positions are remapped onto the numbers the play's surviving paratexts (`origin != "tei"`) leave free, in file order. `write/1` calls `PlayContent.sync_characters/1` before `update_verse_count/1`.

- [ ] **Step 7: Run the tests** — Expected: PASS. Then `mix test test/playcode/import/` whole.
- [ ] **Step 8: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 9: Commit** — `feat(import): every cast list, paratext and scene where its file has it`

---

### Task 3: The export writes each item by its place

**Files:**
- Modify: `lib/playcode/outline.ex`, `lib/playcode/export/tei_xml.ex` (`build_text/5` ~815, `build_front/6` ~831, `build_back/2` ~660, `build_body/1` ~1146, `paratext_element/1` ~1131), `test/support/import_helpers.ex`, `test/playcode/tei_roundtrip_test.exs`

**Interfaces:**
- Consumes: `Outline.items/2`, `PlayContent.list_cast_lists/1`.
- Produces:

```elixir
Outline.placement(items) :: [{:front | :body | :back, Paratext.t() | Division.t()}]
  # body divisions = top-level divisions not of type elenco; before the first :front, after the
  # last :back, between :body; with no body division every item is :front
ImportHelpers.text_order(xml) :: [String.t()]
  # each child of <front>, <body>, <back> in order as "front/div[elenco]", "front/set",
  # "body/div1[acto]", and each div1's castList and div2 children as "body/div1[acto]/castList",
  # "body/div1[acto]/div2[escena]"; "[type]" only when the element has one
```

The encoding, from the spec's table: a paratext `:front`/`:back` as today's `paratext_element/1`, `:body` as `<div1 type=kind>` (the scene as `div1 type="circunstancia_accion"`); a list `:front`/`:back` as `<div type="elenco"><head/><castList/>`, `:body` as `<div1 type="elenco">`; inside an act, a list before the act's first scene as a bare `<castList><head/>…` right after the act's head, one between or after scenes as `<div2 type="elenco"><head/><castList/>`. An entry is a `castItem` (`ana="oculto"` when its character is hidden) with `role` (`xml:id` on its character's first entry in outline order, `corresp="#…"` on later ones, neither when it names no character), its `roleDesc`, and `actor` on the first entry only; consecutive entries with the same non-empty `group_heading` are one `castGroup` with that `head`. `xml:id="castlist"` goes on the first list's `castList`. An empty list is its `div`/`div1`/`div2 type="elenco"` with its head and no `castList`, a bare position included.

- [ ] **Step 1: Write the failing tests** in `tei_roundtrip_test.exs`:

```elixir
test "a file comes back in its own order, every list where it stood" do
  xml = File.read!("test/fixtures/outline.xml")
  assert text_order(roundtrip(xml)) == text_order(xml)
end

test "each role comes back as its file wrote it, ids, references and groups" do
  assert xml_elements(roundtrip(xml), "role") == xml_elements(xml, "role")
  assert xml_texts(roundtrip(xml), "head", within: "castGroup") == ["Criados"]
end

test "a cast list with no entries is written where it stands and read back there"
  # a play built with PlayContent: act 1 with scene 1, an empty elenco child at 1, scene 2;
  # export: text_order includes "body/div1[acto]/div2[elenco]"; import of that export: the act's
  # children are escena, elenco, escena

test "a play with no body division writes every item in its front"
  # a paratext and a list, no act: text_order == ["front/titlePage", "front/div[dedicatoria]", "front/div[elenco]"]

test "a performance cast from the cast list names the first list"
  # two lists, a performance with cast_from_cast_list: the first castList in document order
  # carries xml:id="castlist", the second none
```

- [ ] **Step 2: Run** `mix test test/playcode/tei_roundtrip_test.exs` — Expected: FAIL: one `div type="elenco"` with every role, the loa in `<front>`.

- [ ] **Step 3: Implement** `Outline.placement/1`, `ImportHelpers.text_order/1` and the export above. `build_text/5` takes the lists from `PlayContent.list_cast_lists/1` and works out which entry is each character's first from that same order; nothing reads `paratext.back` or orders by kind any more.

- [ ] **Step 4: Run the tests** — Expected: PASS. Then `mix test --include slow test/playcode/roundtrip_test.exs`: the fixture validates against the TEI schema and the corpus comes back whole. A corpus file that fails here and passed before is this task's bug.

- [ ] **Step 5: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 6: Commit** — `feat(export): each paratext, scene and cast list written where it stands`

---

### Task 4: The complete-copy rule holds the outline

**Files:**
- Modify: `test/playcode/complete_copy_test.exs` (`rare_play/0` ~276, `cast!/2` ~508, `snapshot/1` ~588, the table check ~73)

**Interfaces:**
- Consumes: `PlayContent.create_entry/1`, `create_character/1` (with `cast_list_id`), `list_cast_lists/1`.

- [ ] **Step 1: Extend the rare play and the snapshot.** `rare_play/0` gains: a second list inside act 1 before its scene, and a third between two scenes (a second scene added); a list and a paratext (`kind: "loa"`) between act 1 and a new act 2; a `group_heading` on two consecutive entries; BLAS in two lists with a second description; a list after the text (after the epilogue, which loses `back: true` once Task 6 lands; until then it keeps it). The snapshot gains `cast_lists:` — each list's fields and its entries' fields, `character_id` replaced by the character's `xml_id`. The table check lists `cast_list_entries` among the compared tables.

- [ ] **Step 2: Run** `mix test test/playcode/complete_copy_test.exs` — Expected: PASS. It covers what Tasks 1–3 built, so prove it bites: drop the `corresp` branch in the export's role, watch the rare play fail on BLAS's second entry, restore.

- [ ] **Step 3: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 4: Commit** — `test: the complete copy holds every cast list and the outline's order` (say which line was broken to prove it)

---

### Task 5: The play page and the downloads print the outline

**Files:**
- Modify: `lib/playcode/play_content.ex` (`load_play_content/2` ~613), `lib/playcode_web/components/play_text.ex` (`play_body/1`, `cast_list/1`), `lib/playcode_web/live/play_show_live.ex` (~45-66, ~584-606, `build_sections_navigation`), `lib/playcode/export/html.ex` (~17, ~379), `lib/playcode/export/epub.ex` (~18, ~229, ~247), the tests of each

**Interfaces:**
- Consumes: `Outline.items/2`, the entries preloaded on every list.
- Produces: `load_play_content/2` preloads `entries: :character` on top-level divisions and their children. `PlayText.play_body/1` takes `items` (the outline: paratexts and divisions mixed) in place of `divisions` and `scene`; a paratext prints as the play page's paratext block does now (moved into `PlayText`), a list as `cast_list/1` over **its own** entries (hidden characters left out; a `group_heading` printed once above its run), a division as today, its children in order with a child list printed between its scenes.

- [ ] **Step 1: Write the failing tests**, with the fixture imported and marked complete:
  - `play_show_live_test.exs` — "the text prints the outline in its file's order": the rendered text tab shows, in this order, the dedication's, the list's "PERSONAS", the head title, act 1's head, "Personas del acto primero", scene 1, act 1's second list, scene 2, the list between acts, the loa, act 2, the epilogue, the last list. A small `in_order?(html, strings)` helper in the test (indexes of each string, ascending).
  - same file — "each cast list prints only its own entries": "ANA, disfrazada" once, "Músicos" once, "DIEGO" in one list.
  - same file — "the navigation has an entry per cast list, in order": the play section's labels.
  - `html_test.exs` and the EPUB's test — the same order assertion over the generated document.

- [ ] **Step 2: Run** them — Expected: FAIL (every list prints every character; the loa prints as an act).

- [ ] **Step 3: Implement.** `PlayLabels.split_paratexts/2` leaves these three callers; the page's nav lists every outline item in order (paratexts before the text join the play section too); anchors `outline-<index>`. An existing test asserting `meta-note-*` or `back-paratext-*` anchors is updated, with a comment saying why.

- [ ] **Step 4: Run the tests** — Expected: PASS.
- [ ] **Step 5: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 6: Commit** — `feat: the play page and the downloads print the outline in order`

---

### Task 6: The published site, the comparison, the API; `back` goes

**Files:**
- Create: `priv/repo/migrations/20261020130000_remove_paratext_back.exs`
- Modify: `lib/playcode/export/static_site/components.ex` (~355-398), `lib/playcode/export/static_site/edition.ex`, `lib/playcode/export/static_site/pages/title.html.heex`, `text.html.heex`, `division.html.heex`, `lib/playcode/export/static_site/fingerprint.ex` (if `Outline` is not data access), `lib/playcode/export/compare_html.ex` (~306-365), `lib/playcode_web/live/play_comparison.ex`, `lib/playcode_web/controllers/api/play_controller.ex` (~136-145), `lib/playcode/catalogue/paratext.ex`, `lib/playcode/import/tei_parser.ex`, `lib/playcode_web/play_labels.ex` (`split_paratexts/2` goes), `lib/playcode_web/live/admin/play_content_editor_live.ex` (~1322 badge, ~2723 checkbox), their tests, `test/playcode/complete_copy_test.exs` (the epilogue's `back`)

**Interfaces:**
- Consumes: `Outline.items/2`, `Outline.placement/1`.

- [ ] **Step 1: Write the failing tests:**
  - `static_site_test.exs` — the title page prints the `:front` items in order (the scene before "PERSONAS", the head title after); act 1's page prints its two lists where they stand; the list and the loa between the acts print at the top of act 2's page, above its heading; the epilogue and the last list on the last page; the Contents has an entry per list and per paratext after the title page.
  - the compare page's test — each list prints its own entries where it stands among the divisions (paratexts stay off the comparison, as today).
  - the API's test — the epilogue reads `back: true`, the dedication and the loa `back: false`; a character's `description` is its first entry's.

- [ ] **Step 2: Run** them — Expected: FAIL.

- [ ] **Step 3: Implement.** The site prints a `:body` item on the page of the body division after it; a scene page's slug uses the scene's ordinal among the act's scenes, not its position, which a list now shares. Then drop `play_paratexts.back` (migration), its field, its cast and the "scene stands with the cast list" validation, the parser's `back: true`, the editor's checkbox and badge; the API works `back` out from `Outline.placement/1`. `fingerprint_test.exs` names any module the site now calls that is neither fingerprinted nor data access.

- [ ] **Step 4: Run the tests** — Expected: PASS, `fingerprint_test.exs` included.
- [ ] **Step 5: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 6: Commit** — `feat: the site and the comparison print the outline; a paratext's back is its place`

---

### Task 7: The Structure tab is the outline

**Files:**
- Modify: `lib/playcode/outline.ex`, `lib/playcode/play_content.ex` (`delete_division/1`, `next_division_position/2`), `lib/playcode/catalogue.ex` (`reorder_paratexts/2` goes), `lib/playcode_web/live/admin/play_content_editor_live.ex` (Structure tab ~1612-1745, `new_division` ~444, `delete_division` ~464, `open_new_division/2` ~669, the paratext list ~1295-1330 and `reorder_paratexts` ~252, `.DragSortList` ~1472), its test

**Interfaces:**
- Consumes: `Outline.items/2`, `PlayContent.sync_characters/1`.
- Produces:

```elixir
Outline.reorder(play_id, keys :: [String.t()]) :: :ok
  # keys "paratext:<id>" | "division:<id>"; renumbers both tables' top-level rows 0.. in that
  # order; keys not of this play's top-level rows are dropped; syncs the characters
Outline.next_position(play_id) :: integer   # after the last top-level item, paratexts included
PlayContent.reorder_children(act, ids) :: :ok   # an act's scenes and lists, scoped to the act; syncs
PlayContent.deletion_effect(division) :: %{speaking: [String.t()], removed: non_neg_integer}
  # the characters whose every entry is in this list or this act's lists: names of those who
  # speak (have element_characters), and how many do not
PlayContent.delete_division(division) :: {:ok, Division.t()} | {:error, {:speaking, [String.t()]}}
  # refused while deletion_effect(division).speaking != []; otherwise deletes the division and
  # the characters left with no entry, then syncs
```

The outline: one list of every top-level item, each with a drag handle (`aria-label` "Drag to reorder"), its kind or type badge, its heading, and its actions; an act's children, nested under it, drag within the act only. "Add division" offers the division types and Cast list; "Add subdivision" (on an act) offers Scene and Cast list; "Add paratext" opens the Paratexts tab's form. New items stand last at their level (`Outline.next_position/1`, `next_division_position/2`) and are dragged into place from there. A list row has no "Add subdivision" and no "Edit content". The hook collects only its own container's direct `.drag-item`s, so the act's nested list and the outline's do not take each other's rows. The Paratexts tab loses its drag handles and `reorder_paratexts`.

- [ ] **Step 1: Write the failing tests** in the content editor's test, through `live/2`:
  - "dragging moves a paratext, a list or an act anywhere among the others": `render_hook` on the outline with keys putting the loa first; `outline_items/1` reads the loa first; the export's `text_order` now has the loa in `<front>`.
  - "an act's scenes and lists are dragged within the act".
  - "Add division offers Cast list, which stands last in the outline"; "Add subdivision offers Scene and Cast list".
  - "a cast list offers neither Add subdivision nor Edit content".
  - "deleting a list holding a speaking character's only entry is refused, naming them"; "deleting a list whose characters are elsewhere or silent removes it and those left in no list" (the confirmation reads the count).
  - Review Focus 4: "deleting an act whose list holds a speaking character's only entry is refused".
  - Review Focus 5: a reorder carrying another play's paratext id leaves both plays' orders unchanged; a delete with another play's list id shows the gone flash.

- [ ] **Step 2: Run** them — Expected: FAIL.
- [ ] **Step 3: Implement** the functions and the tab above.
- [ ] **Step 4: Run the tests** — Expected: PASS, `accessibility_test.exs` included.
- [ ] **Step 5: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 6: Commit** — `feat(admin): the Structure tab is the play's outline`

---

### Task 8: The Characters tab, one section per list

**Files:**
- Modify: `lib/playcode/play_content.ex` (`reorder_characters/2` and `shift_character_positions/1` go), `lib/playcode_web/live/admin/play_content_editor_live.ex` (Characters tab ~1395-1470, `reorder_characters` ~257, `delete_character` ~236, the character form ~860-875 and ~213), its test

**Interfaces:**
- Consumes: Task 1's entry functions, `deletion_effect/1`'s rule.
- Produces:

```elixir
PlayContent.reorder_entries(play_id, keys :: [String.t()]) :: :ok
  # keys "list:<id>" and "entry:<id>"; each entry joins the list key before it, positions from 0;
  # keys not of this play dropped; syncs
PlayContent.delete_entry(entry) :: {:ok, CastListEntry.t()} | {:error, {:speaking, [String.t()]}}
  # an entry that is its character's last: refused when the character speaks, otherwise the
  # character goes with it
```

One section per list in outline order, each under its heading (a list in an act labelled with the act's heading before its own), all inside one drag container whose list headers are fixed rows carrying `data-id="list:<id>"`, so a drag pushes the keys above. An entry row shows its name, description, group and, for a linked entry, the character's `xml_id`; one naming no character carries "Names no character". Its form edits the entry's name, description and group, and for a linked entry the character's `xml_id`, actor and hidden flag. "Add character" in a section makes a character and its entry there; "Add an existing character" offers the characters not yet in that list and makes an entry with the character's name.

- [ ] **Step 1: Write the failing tests:**
  - "each list has its own section, in outline order, with its own entries" (fixture imported).
  - "dragging an entry into another list moves it there": `render_hook` with keys moving DIEGO into the first list; `list_cast_lists/1` shows it there.
  - "Add an existing character puts one already listed into this list, and offers none already in it".
  - "editing an entry's description changes that list's line only".
  - "removing a speaking character's last entry is refused, naming them".
  - Review Focus 5: a drag carrying another play's entry key changes nothing; editing an entry deleted meanwhile shows the gone flash.
- [ ] **Step 2: Run** them — Expected: FAIL.
- [ ] **Step 3: Implement** the functions and the tab above; remove `reorder_characters/2`, `shift_character_positions/1` and their events.
- [ ] **Step 4: Run the tests** — Expected: PASS, `accessibility_test.exs` included.
- [ ] **Step 5: Refactor while green**, `mix test`, `mix format`, `mix compile --warnings-as-errors`.
- [ ] **Step 6: Commit** — `feat(admin): the Characters tab, one section per cast list`

---

### Task 9: The corrected files and the paperwork

**Files:**
- Modify: `doc/tei_corpus/EMOTHE0283_*.xml`, `doc/tei_corpus/EMOTHE0555_ElGalanCastrucho.xml` (git-ignored: our copies), `docs/tei-mapping.md`, `docs/schema.md`, `CONTEXT.md`, `docs/stakeholder/ida-y-vuelta.html`, `docs/backlog.md`, `docs/history.md`, and wherever *Mariamne*'s correction (question 8) is recorded (`grep -rn Mariamne docs/`)

- [ ] **Step 1: Correct the two files** as the spec's *The files we correct* says. 0283: one `div type="elenco"`, "Women" a `castGroup` with its head. 0555: lists 2 and 3 move inside acts 2 and 3 as bare `castList`s right after each act's head; their roles become `corresp` to list 1's ids, keeping each act's name and `roleDesc`; SOLDADOS (act 2) and ACOMPAÑA (act 3) keep `xml:id`; ESCOBARILLO2, ESCOBARILLO3 and their kin go. Check: `xmllint --noout` on both; import each into the dev database (`mix playcode.import.tei <file>`); the play page shows 0555's acts each opening with its own list and 0283 one list with "Women"; `mix test --include slow` passes. Record the list of changes beside *Mariamne*'s, for the team's own copies.

- [ ] **Step 2: The docs.** `docs/tei-mapping.md`: the spec's encoding table, `castGroup`, `corresp`, a role with no id, the empty list. `docs/schema.md`: `cast_list_entries`; `characters.name`, `description`, `position` as copies of the first entry; one top-level position sequence; `play_paratexts.back` gone. `CONTEXT.md`: **outline**, **cast list entry**. `ida-y-vuelta.html`: "A cast list per act or part" → Yes in every column, note n11, and the rows for a cast list after the text and a paratext after the cast list; a dated line in the change log. `docs/backlog.md` → `docs/history.md`: *A second cast list*, *A cast list after the text*, *A paratext after the cast list*, with question 32 and *Egle*'s scene noted as built; a backlog line that production's plays get their files' order and lists back from the next re-import (`docs/production-reimport.md`), the corrected 0283 and 0555 among its files.

- [ ] **Step 3: Run** `mix test` — Expected: PASS (`rename_guard_test.exs` included).
- [ ] **Step 4: Commit** — `docs: the play's outline, in the mapping, the schema, the glossary and the round trip`
