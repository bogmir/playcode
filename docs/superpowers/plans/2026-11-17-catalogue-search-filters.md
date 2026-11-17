# Catalogue Search Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The published site's catalogue page becomes its one search: 23 controls over `search/records.js`, full text included, the result always the list of plays, working from `file://` and readable without JavaScript.

**Architecture:** A new script, `catalogue.js`, holds the record filter as pure functions (tested with `node --test`) and a thin page layer that reads the form, the address and the rows. `search.js` keeps the full-text engine behind two entry points and loses its page; `site.js` loses its catalogue code. The form's lists are rendered at build time from the record entries; text suggestions are filled in the browser from the same file. A handful of browser tests drive real headless Chrome over a generated site through the address, since every filter is in it.

**Tech Stack:** HEEx templates, plain browser JavaScript (no modules, no build step), CSS, `node --test`, ExUnit with LazyHTML, headless Chrome for the `:browser` tests.

**Spec:** `docs/superpowers/specs/2026-11-17-plays-without-text-and-record-search-design.md`, section 7.5 (the 23 controls, the rules, scripts and budgets), 7.4 (the entry's keys), and the search half of section 5. The form as the researcher approved it: `docs/superpowers/specs/2026-11-17-buscador-del-catalogo-maqueta.html` (open it; the Spanish labels are final).

**Needs:** plans `2026-11-17-plays-without-text.md` and `2026-11-17-search-record-index.md` merged.

## Global Constraints

- Work on branch `feature/catalogue-search-filters` in a git worktree of its own. Check the branch before every commit.
- Every task is red, green, refactor, then commit. Prove a test bites with `bin/bites` when it passes at once.
- No third-party request, no `fetch`, no module syntax in the site's scripts: data arrives as `<script>` files (`file://`).
- Budgets, asserted in `test/playcode/export/static_site_test.exs` ("the shared assets stay inside the size budget", line 584): `site.js` ≤ 15,000 bytes, `search.js` ≤ 15,000, `catalogue.js` ≤ 15,000 (new), `style.css` ≤ 25,000, `catalogue.css` ≤ 8,000 (new).
- A page links a style or script as `assets/…?v=` with `@site.assets`.
- The two normalisers agree: the browser's is `EMOTHE.normalise` in `site.js`; do not write a second one.
- Without JavaScript `index.html` is the full list of works; the form is `hidden` until `catalogue.js` shows it.
- Interface words in both languages through the site's `t/1`, `ta/2` and `Bilingual.attrs/2`; Spanish from the mock, word for word.
- Plain `mix test PATH`; `node --test test/js/*.test.mjs`; `mix format`; no `Co-Authored-By` trailer.

### The names every task shares

**Controls**, their names in the form and in the address, and the record key each reads (spec 7.5's numbering):

| # | Name | Control | Reads |
|---|---|---|---|
| 1 | `t` | text | `t` joined, and `c` |
| 2 | `a` | text + datalist `dl-a` | `a` |
| 3 | `l` | select | `l` |
| 4 | `o` | select | `o` |
| 5 | `k` | select | `k` |
| 6 | `s` | select | `s` |
| 7 | `f` | select | `f` |
| 8 | `x` | select: `""`, `1` (with), `0` (without) | `x` |
| 9 | `q`, `m`, `in` | search box; radios `m`: `""` starts with, `w` whole word; radios `in`: `""` all, `s` spoken, `d` stage directions, `n` notes | the full-text index |
| 10 | `d` | two number inputs, `d-from` and `d-to` | `d` |
| 11 | `wt` | select | `w[i][0]` |
| 12 | `wc` | text + datalist `dl-wc` | `w[i][1]` |
| 13 | `wy` | `wy-from`, `wy-to` | `w[i][2..3]` |
| 14 | `wf` | select | `w[i][4]` |
| 15 | `rp` | text + datalist `dl-rp` | `r[i][0]` (any) |
| 16 | `rv` | text + datalist `dl-rv` | `r[i][1]` |
| 17 | `rc` | select | `r[i][2]` |
| 18 | `ry` | `ry-from`, `ry-to` | `r[i][3..4]` |
| 19 | `rk` | text + datalist `dl-rk` | `r[i][5]` |
| 20 | `ra` | text + datalist `dl-ra` | `r[i][6]` (any) |
| 21 | `h` | select | `h` |
| 22 | `p` | text + datalist `dl-p` | any name in any list of `p` |
| 23 | `n` | text | any of `n` |
| | `sort` | select: `""` author, `title`, `date` | the work's sort keys |

**The address** is the hash: `index.html#l=en&wy=1600-1610&q=convidado`. A range is `from-to`, `from-` or `-to`. Empty controls are left out; names come in the table's order. `encodeURIComponent` for values.

**`EMOTHE.records`** (in `catalogue.js`, usable with no `document`):

```js
R.load(entries)             // called by search/records.js; keeps them, resolves whoever waits
R.prepare(entry) -> prepared // the entry with its text values normalised (EMOTHE.normalise), made once
R.match(prepared, state) -> boolean   // state: { name: string } as R.parse returns it; text values are normalised inside
R.parse(hash) -> state      // "#l=en&d=1600-" -> { l: "en", d: "1600-" }; unknown names dropped
R.format(state) -> string   // the inverse, without "#"; "" for an empty state
R.shown(works, passing) -> { rows: { CODE: "show" | "muted" | "hide" }, count: number }
                            // works: [[leadCode, code, …], …]; passing: { CODE: true }
```

**`EMOTHE.search`** (in `search.js`), the two entry points the catalogue calls; its pure functions (`parse`, `hits`, `intersect`, `decode`, `matches`, `hasPhrase`, `shardKey`, `shardFile`, `chunkKey`, `kind`) stay as they are:

```js
S.find(query, mode) -> Promise<{ CODE: [[line, kind], …] }>   // mode "prefix" | "word"; kind "spoken" | "stage" | "note"; lines ascending; {} for no word
S.passages(code, lines) -> Promise<[{ href, ref, speaker, kind, text }]>   // href "plays/CODE/<slug>.html#<anchor>"; loads the chunks it needs
```

## Review Focus

1. **A reader opens a shared address before anything is loaded** (`index.html#rk=king&q=honour`): `records.js` and the full-text index load at once and the list is filtered when both land, not left unfiltered. Browser test in Task 6.
2. **A range typed backwards or half-filled** (`wy=1610-1600`, `d=1600-`): backwards matches nothing, half-filled is open-ended. Node test in Task 1.
3. **Accents, case and ñ in typed text** ("calderon" finds "Calderón", "ano" does not find "año"): through `EMOTHE.normalise`. Node test in Task 1.
4. **A play with a witness in London and another in quarto, asked for "London quarto"**: not found, since no one witness is both. Node test in Task 1.
5. **A site with no witness, performance or place at all** (a small site, a test site): the groups' lists hold only "Todas", nothing breaks, and the build does not fail on an empty list. Elixir test in Task 4.

---

### Task 1: The record filter

**Files:**
- Create: `priv/static_site/catalogue.js` (the pure half only: `EMOTHE.records.load`, `prepare`, `match`)
- Test: `test/js/catalogue.test.mjs` (new; load `site.js` then `catalogue.js` into a `vm` context as `test/js/search.test.mjs` does)

**Interfaces:**
- Consumes: `EMOTHE.normalise` (`site.js`); the entry shape of spec 7.4.
- Produces: `R.load`, `R.prepare`, `R.match` as above.

- [ ] **Step 1: Write the failing tests.** One fixture entry, then a table of states:

```js
const hamlet = { c: 'EMOTHE0010', t: ['Hamlet', 'The Tragedy of Hamlet'], a: 'William Shakespeare', l: 'es', o: 'en',
  k: 'translation', s: 'EMOTHE', f: 'verse', x: 1, d: [1599, 1601], h: 'edad_media',
  w: [['early_edition', 'London', 1604, 1605, '4º'], ['collection', 'Madrid', 1623, 1623, '2º'], ['manuscript', null, null, null, null]],
  r: [[['London', 'England', 'Inglaterra'], 'The Globe', 'commercial_theatre', 1601, 1601, 'The King’s Men', ['Richard Burbage']],
      [[], null, 'palace', 1619, 1620, null, []]],
  p: [['Elsinor', 'Elsinore', 'Dinamarca', 'Denmark']], n: ['HAMLET', 'OFELIA', 'Calderón'] };
const bare = { c: 'EMOTHE0596', t: ['L’abuseur de Séville'], l: 'fr', o: 'fr', k: 'original', s: 'EMOTHE' };
const yes = (entry, state) => assert.equal(R.match(R.prepare(entry), state), true, JSON.stringify(state));
const no = (entry, state) => assert.equal(R.match(R.prepare(entry), state), false, JSON.stringify(state));

test('an empty state matches every play', () => { yes(hamlet, {}); yes(bare, {}); });
test('text is a normalised substring', () => {
  yes(hamlet, { t: 'tragedy' }); yes(hamlet, { t: 'emothe0010' }); yes(hamlet, { a: 'SHAKES' });
  yes(hamlet, { n: 'calderon' }); no(hamlet, { n: 'ofelio' }); yes(bare, { t: 'seville' });
  no(bare, { a: 'x' });                                   // no author matches no author text
});
test('ñ is not n', () => { no({ c: 'X', t: ['El año'] }, { t: 'ano' }); yes({ c: 'X', t: ['El año'] }, { t: 'AÑO' }); });
test('a list wants its value', () => {
  yes(hamlet, { l: 'es', o: 'en', k: 'translation', s: 'EMOTHE', f: 'verse', h: 'edad_media' });
  no(hamlet, { l: 'en' }); no(bare, { f: 'prose' }); no(bare, { h: 'edad_media' });
});
test('with or without text', () => { yes(hamlet, { x: '1' }); no(hamlet, { x: '0' }); yes(bare, { x: '0' }); no(bare, { x: '1' }); });
test('a range overlaps', () => {
  yes(hamlet, { d: '1601-1610' }); yes(hamlet, { d: '1590-' }); yes(hamlet, { d: '-1599' });
  no(hamlet, { d: '1602-' }); no(hamlet, { d: '1610-1600' }); no(bare, { d: '1500-1700' });   // backwards; no dating
});
test('witness fields are met by one witness', () => {
  yes(hamlet, { wt: 'early_edition', wc: 'london', wy: '1600-1610', wf: '4º' });
  no(hamlet, { wc: 'london', wf: '2º' });                  // London is the quarto, Madrid the folio
  no(hamlet, { wt: 'manuscript', wy: '1500-1700' });       // a witness with no year matches no range
  yes(hamlet, { wt: 'manuscript' });
});
test('performance fields are met by one performance', () => {
  yes(hamlet, { rp: 'inglaterra', rv: 'globe', rc: 'commercial_theatre', ry: '1601-1601', rk: 'king', ra: 'burbage' });
  no(hamlet, { rc: 'palace', rk: 'king' });
  yes(hamlet, { rc: 'palace', ry: '1620-' });
});
test('a place of action is found by any of its names, or a containing place', () => {
  yes(hamlet, { p: 'elsinore' }); yes(hamlet, { p: 'dinamarca' }); no(hamlet, { p: 'sevilla' });
});
test('filters combine with and', () => { no(hamlet, { l: 'es', n: 'nadie' }); });
test('q, m, in and sort are not record filters', () => { yes(bare, { q: 'honor', m: 'w', in: 'n', sort: 'date' }); });
```

- [ ] **Step 2: Run** `node --test test/js/catalogue.test.mjs` — expected: FAIL, cannot read `catalogue.js` (ENOENT).

- [ ] **Step 3: Implement** the three functions in the file's IIFE, in the style of `search.js` (ES5-ish, `var`, no modules), ending the pure half with `if (!root.document) return;`. A range parses to `[from, to]` with a missing end open; a group's fields (`w*`, `r*`) are tested together with `some` over the tuples.

- [ ] **Step 4: Run** it — expected: PASS.

- [ ] **Step 5: Refactor while green.** One table drives the simple fields (name, key, kind: text or list), so a field is a row, not a branch.

- [ ] **Step 6: Commit** — `feat: the catalogue's record filter`

---

### Task 2: The address, and which rows show

**Files:**
- Modify: `priv/static_site/catalogue.js` (`R.parse`, `R.format`, `R.shown`)
- Test: `test/js/catalogue.test.mjs`

- [ ] **Step 1: Write the failing tests.**

```js
test('the address round-trips, in the table’s order, empty values left out', () => {
  const state = { l: 'en', q: 'la vida', wy: '1600-1610', a: 'Calderón' };
  assert.equal(R.format(state), 'a=Calder%C3%B3n&l=en&q=la%20vida&wy=1600-1610');
  assert.deepEqual(plain(R.parse('#' + R.format(state))), state);
  assert.equal(R.format({ l: '', t: '  ' }), '');
  assert.deepEqual(plain(R.parse('#nope=1&l=en')), { l: 'en' });
  assert.deepEqual(plain(R.parse('')), {});
});
test('a work shows when any of its plays passes; its lead stays, muted, to head it', () => {
  const works = [['A', 'A1', 'A2'], ['B'], ['C', 'C1']];
  assert.deepEqual(plain(R.shown(works, { A1: true, B: true })), {
    rows: { A: 'muted', A1: 'show', A2: 'hide', B: 'show', C: 'hide', C1: 'hide' }, count: 2 });
  assert.equal(R.shown(works, { A: true, A1: true, A2: true, B: true, C: true, C1: true }).count, 6);
});
```

`R.format`'s order is the table's: `t a l o k s f x q m in d wt wc wy wf rp rv rc ry rk ra h p n sort`.

- [ ] **Step 2: Run** — expected: FAIL, `R.parse is not a function`.
- [ ] **Step 3: Implement.** `R.parse` splits on `&` and `=` and decodes; `URLSearchParams` is fine in browsers and Node alike.
- [ ] **Step 4: Run** — expected: PASS.
- [ ] **Step 5: Refactor while green; commit** — `feat: the catalogue's search state lives in the address`

---

### Task 3: The full-text engine behind two entry points

**Files:**
- Modify: `priv/static_site/search.js` (everything after `if (!root.document) return;` at line 99: `need`, `loadLines`, `lineOf`, `pairsOf`, `phraseFilter` stay; `run`, `passes`, `render`, `renderFacets`, `group`, `hit`, `highlight`, the `FACETS` table, the `DOMContentLoaded` handler and the page's variables go)
- Test: `test/js/search.test.mjs` (the pure tests stay green); the new entry points are exercised in Task 6's browser tests

**Interfaces:**
- Produces: `S.find(query, mode)` and `S.passages(code, lines)` as in *The names every task shares*. `S.find` is `run`'s promise chain without the page: load `search/plays.js`, the shards, intersect, filter phrases, then group the `"play:line"` hits by the play's code. `S.passages` maps each line through `lineOf` to `{ href: 'plays/' + code + '/' + row[0] + '.html#' + row[1], ref: row[2], speaker: speakers[row[3]] || null, kind: row[4], text: row[5] }`.

- [ ] **Step 1: Write the failing test** in `test/js/search.test.mjs`: with `S.load` fed a `plays` list of two plays and one `index` shard by hand, and a stub `document` that is never touched because every file is already loaded, `await S.find('sueno', 'prefix')` deep-equals `{ EMOTHE0001: [[3, 'spoken'], [9, 'stage']] }`, and `await S.find('  ', 'prefix')` is `{}`. The vm context needs `document: { head: { appendChild() {} }, createElement: () => ({}) }` for the file's second half to load; say so in a comment.
- [ ] **Step 2: Run** `node --test test/js/search.test.mjs` — expected: FAIL, `S.find is not a function`.
- [ ] **Step 3: Implement** the two functions and delete the page code. Keep the `S.NOTE_BASE`/`S.LINES_PER_CHUNK` comments and the tests that tie them to `Search`.
- [ ] **Step 4: Run** `node --test test/js/*.test.mjs` — expected: PASS. `wc -c priv/static_site/search.js` — expected: well under 15,000 (it loses about half).
- [ ] **Step 5: Refactor while green.** Nothing in `search.js` names an element of a page.
- [ ] **Step 6:** `search.html` is broken between this task and Task 5; do not merge between them. Commit — `refactor: the full-text search is an engine with two entry points`

---

### Task 4: The page: one form, the lists, the rows

**Files:**
- Modify: `lib/playcode/export/static_site/pages/catalogue.html.heex` (the whole rail and controls)
- Modify: `lib/playcode/export/static_site/pages/search.html.heex` (becomes a redirect) and `lib/playcode/export/static_site/pages.ex` (`search_words/0` near line 45 becomes the catalogue's words)
- Modify: `lib/playcode/export/static_site/components.ex` (`shell/1`: the nav's Search entry near line 81 goes, an optional `stylesheet` attr; `catalogue_entry/1` at 1576: `data-code`, the five filter attributes go)
- Modify: `lib/playcode/export/static_site.ex` (`write_catalogue/3` at 627, `facets/1` at 712 gives way to `lists/1`)
- Modify: `lib/playcode/export/static_site/records.ex` (`entries/2` public; `write/2` takes the entries)
- Create: `priv/static_site/catalogue.css`; Modify: `priv/static_site/style.css` (the catalogue-only rules leave: lines 247-264 and `.entry .compare` at 102-104, each only if no other page's template uses its class — `grep -rn 'class=' lib/playcode/export/static_site`)
- Test: `test/playcode/export/static_site_catalogue_test.exs`, `test/playcode/export/static_site_search_test.exs` (lines 121, 140, 503 change), `test/playcode/export/static_site_test.exs` (budgets), `test/playcode/export/static_site_records_test.exs` (the query-count test's call)

**Interfaces:**
- Changes plan 2's interface: `Records.entries(plays, roots) :: [map()]` (public) and `Records.write(dir, entries) :: non_neg_integer()`.
- Produces: `index.html` with `<form data-search hidden data-words=…>` holding every control of the table by its `name`, each `<select>`'s options from the published plays' values; `[data-works] > li[data-work]` rows whose plays are `[data-play][data-code]`; `<link rel="stylesheet" href="assets/catalogue.css?v=…">` and `<script src="assets/catalogue.js?v=…" defer>`; the stamp also on the form as `data-assets` for the scripts `catalogue.js` adds later.

- [ ] **Step 1: Write the failing tests** in `static_site_catalogue_test.exs` (replace "facets count the plays…", "the Form facet follows…" and "each entry carries what the filter and facets match on" with these, noting in the commit that the same behaviour is asserted in its new place):

```elixir
@names ~w(t a l o k s f x q m in d-from d-to wt wc wy-from wy-to wf rp rv rc ry-from ry-to rk ra h p n sort)

test "the form holds every control, named, labelled, and hidden until the script shows it" do
  page = html!(generate!([complete_play()]), "index.html", "es")
  form = LazyHTML.query(page, "form[data-search]")
  assert LazyHTML.attribute(form, "hidden") == [""]
  for name <- @names, do: assert {name, LazyHTML.query(form, ~s([name="#{name}"])) |> Enum.empty?()} == {name, false}
  # every input and select is named by a label or an aria-label
  for control <- LazyHTML.query(form, "input:not([type=radio]), select"), do: assert labelled?(form, control)
  assert texts(form, "details > summary") |> Enum.map(&squish/1) |> Enum.map(&hd(String.split(&1, " ("))) ==
           ["Obra", "Datación", "Testimonios", "Representaciones", "Tiempo y lugar", "Personajes"]
end

test "a list offers the values the published plays hold, the first four with their counts" do
  plays = [complete_play(%{"language" => "es"}), complete_play(%{"language" => "es"}), complete_play(%{"language" => "en", "form" => "prose"})]
  page = html!(generate!(plays), "index.html", "es")
  assert options(page, "l") == [{"", "Todos"}, {"es", "Español (2)"}, {"en", "Inglés (1)"}]
  assert {"prose", "Prosa (1)"} in options(page, "f")
  assert options(page, "x") == [{"", "Todas"}, {"1", "Con texto"}, {"0", "Sin texto"}]
end

test "a site with no witness, performance or place offers only the first option there" do   # Review Focus 5
  page = html!(generate!([complete_play()]), "index.html", "es")
  for name <- ~w(wt wf rc h), do: assert [{"", _all}] = options(page, name)
end

test "a list's options follow the interface's language" do
  play = complete_play()
  witness!(play, %{"witness_type" => "manuscript"})
  dir = generate!([play])
  assert {"manuscript", "Manuscrito"} in options(html!(dir, "index.html", "es"), "wt")
  assert {"manuscript", "Manuscript"} in options(html!(dir, "index.html", "en"), "wt")
end

test "a row names its play by code and carries no filter data; a work names its plays" do
  play = complete_play()
  row = html!(generate!([play]), "index.html") |> LazyHTML.query("[data-play]")
  assert LazyHTML.attribute(row, "data-code") == [play.code]
  for gone <- ~w(data-lang data-form data-kind data-coll data-text), do: assert LazyHTML.attribute(row, gone) == []
end

test "the page links its own stylesheet and script, stamped, and the site has no Search entry" do
  page = html!(generate!([complete_play()]), "index.html")
  assert [href] = page |> LazyHTML.query(~s(link[href^="assets/catalogue.css"])) |> LazyHTML.attribute("href")
  assert href =~ ~r/\?v=[0-9a-f]{12}\z/
  assert [_src] = page |> LazyHTML.query(~s(script[src^="assets/catalogue.js?v="])) |> LazyHTML.attribute("src")
  refute "search.html" in (page |> LazyHTML.query("nav.site a") |> LazyHTML.attribute("href"))
end

test "the old search page sends its reader, and their words, to the catalogue" do
  page = read!(generate!([complete_play()]), "search.html")
  assert page =~ ~s(http-equiv="refresh")
  assert page =~ "index.html"
  assert page =~ "#q="            # the inline script that carries ?q= over
end
```

`complete_play/1` is `play_fixture(Map.put(attrs, "is_complete", true))`, as `static_site_changes_test.exs` defines it; `witness!/2` is plan 2's helper in `static_site_records_test.exs` (move both to `test/support/static_site_helpers.ex` rather than copy them). `options/2` and `labelled?/2` are private helpers of the test file (`{value, text}` pairs of a select by name; a `label[for]`, a wrapping label or an `aria-label`). `html!/3` with `"es"`/`"en"` gives the page as that interface reads it; if it does not resolve `data-en-label` on an `<option>`, assert on the attribute pair instead.

In `static_site_test.exs`, the budget test gains `assert size.("catalogue.js") <= 15_000` and `assert size.("catalogue.css") <= 8_000`.

- [ ] **Step 2: Run** `mix test test/playcode/export/static_site_catalogue_test.exs test/playcode/export/static_site_test.exs` — expected: FAIL, no `form[data-search]`.

- [ ] **Step 3: Implement.**
  - `Records.entries/2` public; `write_catalogue/3` computes the entries once, passes them to `Records.write/2` and to `lists/1`.
  - `lists(entries)`: for `l o k s f` the values with their counts, most frequent first; for `wt wf rc h` the values present, in their vocabulary's own order (`PlayLabels.witness_type_options/0`, `Performance.venue_types/0`, `Play.historical_times/0`; formats sorted). Labels as pairs: `Components.language/1`, `Components.kind_label/1`, `same/1` for a collection and a format, `pair(fn -> PlayLabels.form_label(v) end)`, `pair(fn -> PlayLabels.witness_type_label(v) end)`, `{Performance.venue_type_label(v, "es"), Performance.venue_type_label(v, "en")}`, `pair(fn -> PlayLabels.historical_time_label(v) end)`. An option is `<option value={v} {Bilingual.attrs(label, "label")}>`; with a count, the count is in both halves of the pair.
  - The template: the rail's `<form data-search hidden>` with six `<details>` (the first `open`) as the mock lays them out; the search box, the `m` and `in` radios, the count and the sort above the list, inside the same form (`form="…"` attributes if the markup needs them apart). Every datalist is empty in the HTML. `<p data-count aria-live="polite">`.
  - `search.html`: the redirect of `pages/redirect.html.heex`'s shape, to `index.html`, with one inline script before the meta refresh takes effect: `location.replace('index.html' + (/[?&]q=([^&]*)/.test(location.search) ? '#q=' + RegExp.$1 : ''))`.
  - `catalogue.css`: the moved rules plus the form's (`details`, `summary`, labels, the range's two boxes, `.entry.muted`, `.passages`). `style.css` must end smaller than it started.
  - `Pages`: the words `catalogue.js` says (`of`, `plays`, `passage`, `passages`, `searching`, `show more`, `no results`), each a pair, on the form's `data-words`.

- [ ] **Step 4: Run** `mix test test/playcode/export` — expected: PASS, after updating the three tests of `static_site_search_test.exs` that read the old search page (121: the words are now the catalogue's; 140 stays, `plays.js` is unchanged; 503: the search page is a redirect, and the catalogue is the list without JavaScript).

- [ ] **Step 5: Refactor while green.** The template's 23 controls come from three small function components (`text`, `list`, `range`), not 23 hand-written blocks.

- [ ] **Step 6: Commit** — `feat: the catalogue page holds the search form, its lists built from the records`

---

### Task 5: The page comes alive

**Files:**
- Modify: `priv/static_site/catalogue.js` (the half after `if (!root.document) return;`)
- Modify: `priv/static_site/site.js` (`initCatalogue` at line 111 and its call at 299 go)
- Modify: `test/test_helper.exs` (`exclude: [:slow, :browser]`, with the comment saying how to run them)
- Create: `test/support/browser.ex` (`Playcode.Browser.dom!/2`)
- Test: `test/playcode/export/static_site_browser_test.exs` (new, `@moduletag :browser`)

**Interfaces:**
- Produces: `Playcode.Browser.dom!(dir, address) :: LazyHTML.t()` — runs `google-chrome --headless=new --disable-gpu --allow-file-access-from-files --virtual-time-budget=5000 --dump-dom "file://DIR/ADDRESS"` (the binary from `System.find_executable/1` over `google-chrome`, `chromium`, `chromium-browser`; the test is skipped with a message when none is found) and parses what it prints: the page after its scripts ran.
- The page layer: on load, show the form; read the address into the controls; on `input`/`change`, write the address (`history.replaceState`, in a `try` since `file://` may refuse) and filter; on `hashchange`, read again. `records.js` is added as a `<script src="search/records.js">` on the first `focusin` or `input` in the form, or at once when the address holds any record filter. Filtering: `R.shown(works, passing)` sets `hidden` on rows and works and the class `muted` on a muted lead, and `[data-count]` says "N obras de M" / "N of M plays" (nothing when all show). Sorting as `site.js` did. The "Limpiar filtros" button empties the controls and the address. Datalists are filled once from the loaded entries, values deduplicated and sorted with `localeCompare`.

- [ ] **Step 1: Write the failing browser tests.** A `setup_all` builds one site of five plays and keeps its folder: an English original with a witness (`loose`, London, 1604, 4º) and a performance by "The King’s Men"; its Spanish translation; a French play without a text; a Spanish prose play; a Spanish verse play with the character "CLARÍN". Each test asks `Browser.dom!(dir, "index.html#…")` and reads the rows:

```elixir
defp shown(page), do: page |> LazyHTML.query("[data-play]:not([hidden])") |> LazyHTML.attribute("data-code") |> Enum.sort()

test "with no filter every play shows and the form is visible", %{dir: dir, plays: plays} do
  page = Browser.dom!(dir, "index.html")
  assert shown(page) == Enum.sort(Enum.map(plays, & &1.code))
  assert LazyHTML.attribute(LazyHTML.query(page, "form[data-search]"), "hidden") == []
end

test "a list filter in the address hides the rest and fills its control", %{dir: dir, french: french} do
  page = Browser.dom!(dir, "index.html#x=0")
  assert shown(page) == [french.code]
  assert selected(page, "x") == "0"
  assert texts(page, "[data-count]") == ["1 obra de 5"]
end

test "witness fields meet in one witness", %{dir: dir, english: english} do
  assert shown(Browser.dom!(dir, "index.html#wc=london&wy=1600-1610&wf=4%C2%BA")) == [english.code]
  assert shown(Browser.dom!(dir, "index.html#wc=london&wf=2%C2%BA")) == []
end

test "a translation that passes shows under its lead, muted", %{dir: dir, english: english, translation: translation} do
  page = Browser.dom!(dir, "index.html#l=es&o=en")
  assert shown(page) == Enum.sort([english.code, translation.code])
  assert page |> LazyHTML.query(~s([data-code="#{english.code}"].muted)) |> Enum.count() == 1
end

test "suggestions are filled from the records", %{dir: dir} do
  page = Browser.dom!(dir, "index.html#rk=king")
  assert "The King’s Men" in (page |> LazyHTML.query("#dl-rk option") |> LazyHTML.attribute("value"))
end

test "a character is found without its accent", %{dir: dir, verse: verse} do
  assert shown(Browser.dom!(dir, "index.html#n=clarin")) == [verse.code]
end
```

- [ ] **Step 2: Run** `mix test --include browser test/playcode/export/static_site_browser_test.exs` — expected: FAIL: the form is still hidden and every row shows.

- [ ] **Step 3: Implement** the page layer. Delete `initCatalogue` from `site.js`.

- [ ] **Step 4: Run** the browser tests, `mix test test/playcode/export`, `node --test test/js/*.test.mjs` — expected: PASS. `wc -c priv/static_site/*.js priv/static_site/*.css` against the budgets.

- [ ] **Step 5: Refactor while green.** The page layer never decides a match: it calls `R.match` and `R.shown`. One function reads the form into a state, one writes a state into the form.

- [ ] **Step 6: Commit** — `feat: the catalogue filters its plays by any field of their record`

---

### Task 6: Full text in the same list

**Files:**
- Modify: `priv/static_site/catalogue.js`
- Modify: `priv/static_site/catalogue.css` (`.passages`)
- Test: `test/playcode/export/static_site_browser_test.exs`

**Interfaces:**
- Consumes: `S.find/2`, `S.passages/2` (Task 3). With words in `q`, the page adds `<script src="assets/search.js?v=STAMP">` once (the stamp from the form's `data-assets`), then `S.find(q, m === 'w' ? 'word' : 'prefix')`. A play passes when it has a hit of the kind `in` asks for (`s` spoken, `d` stage, `n` note; none: any) and passes the record filter. Each passing row gains, after its entry, `<span class="meta" data-hits>N pasajes</span>` and `<details class="passages">`; opening it calls `S.passages(code, firstFiveLines)` and prints each as `<p><a href=…><span class="ref">ref · speaker</span></a> text</p>` with the found words in `<mark>`, and a "show more" button while lines remain. A second search clears the first's rows. While loading, `[data-count]` says "Buscando…".

- [ ] **Step 1: Write the failing browser tests** on the same site, whose verse play holds the line "es un sueño la vida" and a note with the word "sueño", and whose prose play holds "soñar":

```elixir
test "words in q keep the plays that hold them, each with its count", %{dir: dir, verse: verse} do
  page = Browser.dom!(dir, "index.html#q=sue%C3%B1o")
  assert shown(page) == [verse.code]
  assert texts(page, ~s([data-code="#{verse.code}"] ~ [data-hits])) == ["2 pasajes"]
end

test "where narrows the hits", %{dir: dir, verse: verse} do
  assert texts(Browser.dom!(dir, "index.html#q=sue%C3%B1o&in=n"), "[data-hits]") == ["1 pasaje"]
  assert shown(Browser.dom!(dir, "index.html#q=sue%C3%B1o&in=d")) == []
  _ = verse
end

test "full text and record filters combine, from a cold address", %{dir: dir, verse: verse} do   # Review Focus 1
  assert shown(Browser.dom!(dir, "index.html#f=verse&q=sue")) == [verse.code]
  assert shown(Browser.dom!(dir, "index.html#f=prose&q=sue%C3%B1o")) == []
end

test "a play without a text never has a hit", %{dir: dir, french: french} do
  refute french.code in shown(Browser.dom!(dir, "index.html#q=a&x=0"))
end
```

Opening a row's passages needs a click, which `--dump-dom` cannot make: cover the rendering of a passage with a node test of a pure `R.marked(text, words, mode)` (the text split into plain and marked pieces, as `highlight` did), and check the opened row by hand in Step 5.

- [ ] **Step 2: Run** — expected: FAIL, every play still shows for `#q=…`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the browser tests, `node --test test/js/*.test.mjs`, `mix test test/playcode/export` — expected: PASS; the budgets hold.
- [ ] **Step 5: By hand, from disk.** `mix playcode.export.site --all -o /tmp/site-search`, open `/tmp/site-search/index.html` as `file://` in a browser: type in each of the six groups; search "honor"; open a row's passages and follow one link to its line; "Limpiar filtros"; Back and Forward; switch the interface to English; turn JavaScript off and reload (the full list, no form). Note in the commit body what you did and saw.
- [ ] **Step 6: Refactor while green; commit** — `feat: the catalogue searches the texts and notes in the same list`

---

### Task 7: The documents, the whole suite

**Files:**
- Modify: `docs/static-site.md` (the merged search, `catalogue.js`, `catalogue.css`, the budgets, the `:browser` tests), `docs/architecture.md` (file map), `CLAUDE.md` (the *Static site export* block's budgets line and its normaliser line; the *Commands* table gains `mix test --include browser`)
- Modify: `docs/backlog.md` and `docs/history.md` (the record search done; *Performances: search and pages for companies and actors* keeps its pages-and-merging half; a new item "Old form fields not carried": genre, translator, translation year, criticism year, annotated, collated)

- [ ] **Step 1:** Write the documents.
- [ ] **Step 2: Run** `mix precommit`, `mix test --include browser test/playcode/export/static_site_browser_test.exs`, `node --test test/js/*.test.mjs` — expected: 0 failures each. Paste the three summaries into the commit body.
- [ ] **Step 3: Commit** — `docs: the catalogue is the site's one search`
- [ ] **Step 4:** Tell the owner the branch is ready to merge, and that the published site changes for every reader at the next Deploy. No pull request; merge and push only when told.
