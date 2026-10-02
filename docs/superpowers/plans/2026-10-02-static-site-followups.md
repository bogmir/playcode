# Static Site Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the static site's first search and its longest pages inside their size budgets, make builds parallel and the search index incremental so the admin page never freezes, and let a curator override a play's verse/prose label.

**Architecture:** The search index changes format: lines files split into 100-line chunks, shard postings delta-encoded, and `Search.write_index/3` carries every play's postings over from the shards already on disk, so adding or removing a play touches only that play. `StaticSite.generate/1` builds plays with `Task.async_stream`. `StaticSite.Edition` gives a division with more than 120,000 bytes of text a page per scene. A nullable `plays.form` column overrides the automatic label, read everywhere through `Play.form/1`.

**Tech Stack:** Elixir 1.19.5 / OTP 28.1, Phoenix 1.8.3, LiveView 1.1.22, Ecto/PostgreSQL, Jason, LazyHTML (tests), plain ES2017 JS tested with `node --test`.

**Spec:** `docs/superpowers/specs/2026-10-02-static-site-followups-design.md`. It amends `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`; read the follow-ups spec before Task 1.

## Global Constraints

- No new Hex dependencies and no npm. Node runs only `test/js/search.test.mjs`.
- The generated site makes no third-party requests and works from `file://`, search included: data files are `.js` calling `EMOTHE.search.load(kind, key, data)`; never `fetch`.
- The archive is in English whatever the admin's locale: every `StaticSite` entry point runs inside `Gettext.with_locale(PlaycodeWeb.Gettext, "en", …)`.
- Lower-case `emothe` never appears in a tracked file (`test/rename_guard_test.exs`); the JS global stays `EMOTHE`.
- Every path built from a play code goes through `StaticSite.safe_code!/1`.
- Lines per chunk: **100**, written once in `test/fixtures/search_normalisation.json` as `"lines_per_chunk": 100` and asserted by both the Elixir and the Node tests.
- Shard postings: `[play, n, d1 … dn, …]`, plays ascending, `d = (line − previous line) × 2 + flag`, previous starting at 0 for each play, flag 1 for a stage direction.
- Scene pages: a top-level division gets a page per scene when its text exceeds **120,000 bytes** and it has **at least two scenes with text**.
- `plays.form` is `nil`, `"verse"`, `"prose"` or `"mixed"`; `Play.form/1` is the only reader.
- CLAUDE.md testing rules apply to every task: failing test first, run it red, smallest implementation, green, then the whole `mix test`; test through the outermost API; select by stable id, `data-*`, ARIA or visible text, never CSS classes; a test written for behaviour that already works must be shown to bite.
- After every task: `mix format`, `mix compile --warnings-as-errors`, `mix test` (and `node --test test/js/search.test.mjs` when JS changed). Run mix plainly, never with `export PATH=…`.
- Stage files by path; never a bare `git add -A`, `git add .` or `git commit -a`.

## Review Focus

1. **A site built before this change.** Its `search/lines/<CODE>.js` files and triple-encoded shards must not be read as the new format when one play is added or removed: the whole index is rebuilt instead. Task 3, "a site whose index predates chunked lines is re-indexed in full".
2. **Removing the last play.** The site must still build: an empty `plays.js`, no shards, a catalogue of zero plays. Task 3, "removing the last play leaves an empty site that still builds".
3. **A line on a chunk boundary.** Line 99 lives in chunk 0 and line 100 in chunk 1, on both sides. Task 1 ("a long play's lines are written in chunks of 100…") and Task 2 (`chunkKey`).
4. **A long division with text before its first scene.** That text stays on the division's own page, which also links its scene pages; nothing is lost from `text.html`. Task 5, "gets a page per scene, walked in order".
5. **A play set to "verse" that has no verse.** The title page says "Verse", not "Verse · 0 verses". Task 7, "the title page names the curator's form".

---

## File map

| File | Change |
|---|---|
| `lib/playcode/export/static_site/search.ex` | Chunked lines, delta postings, carried index, `indexed_codes/1`, `lines_per_chunk/0` |
| `priv/static_site/search.js` | Decoder, chunk addressing, ten plays first |
| `lib/playcode/export/static_site.ex` | Parallel `generate/1`, incremental `rebuild_index/2`, family title pages, `Play.form/1` facet |
| `lib/playcode/export/static_site/edition.ex` | Scene pages for long divisions; `scene_page/2`, `scene_title/1` |
| `lib/playcode/export/static_site/components.ex` | `page_text/1`, contents with scene pages, `form_summary/2`, catalogue form |
| `lib/playcode/export/static_site/pages/{division,text,title,statistics}.html.heex` | Use the above |
| `lib/playcode_web/live/admin/export_site_live.ex` | Switching a play off runs in a task |
| `priv/repo/migrations/20261002120000_add_form_to_plays.exs` | `plays.form` |
| `lib/playcode/catalogue/play.ex` | `form` field, `forms/0`, `form/1` |
| `lib/playcode/import/tei_parser.ex` | `:form` in `@platform_owned` |
| `lib/playcode_web/play_labels.ex` | `form_label/1`, `form_options/1` |
| `lib/playcode_web/live/admin/play_form_live.ex` | Form select replaces the "Verse play" checkbox |
| `lib/playcode_web/live/play_show_live.ex` | Form line through `Play.form/1` |
| `test/fixtures/search_normalisation.json`, `test/js/search.test.mjs`, `test/playcode/export/static_site_*_test.exs`, `test/playcode_web/live/admin/{export_site,play_form}_live_test.exs`, `test/playcode/import/{tei_preview,tei_reimport}_test.exs`, `test/playcode_web/live/play_show_live_test.exs` | Tests |
| `CLAUDE.md`, `docs/static-site-improvements.md` | Docs (Task 8) |

---

### Task 1: Search data in chunks, postings delta-encoded

**Files:**
- Modify: `lib/playcode/export/static_site/search.ex`, `lib/playcode/export/static_site.ex`
- Modify: `test/fixtures/search_normalisation.json`
- Test: `test/playcode/export/static_site_search_test.exs`

**Interfaces:**
- Produces: `Search.lines_per_chunk() :: 100`; `Search.write_play(dir, edition) :: %{word => [{line, flag}]}` (lines ascending) — writes `search/lines/<CODE>/<k>.js` as `load("lines", "<CODE>/<k>", %{"speakers" => [name], "lines" => [[slug, anchor, ref, speaker_index | nil, "v" | "p" | "s", text]]})`, speaker indexes local to the chunk; `Search.write_index(dir, plays, postings) :: %{index_bytes, largest_shard_bytes}` where `postings :: %{code => %{word => [{line, flag}]}}`; shards in the delta format of the Global Constraints.
- `StaticSite.write_index_pages/4` now takes the postings map instead of a results list.

- [ ] **Step 1: Add the chunk size to the shared fixture**

In `test/fixtures/search_normalisation.json`, add a top-level key after `"shards"`'s closing bracket (keep the file valid JSON):

```json
  ,
  "lines_per_chunk": 100
```

so the file ends `…{"word": "1236", "key": "12", "file": "12"}\n  ],\n  "lines_per_chunk": 100\n}`.

- [ ] **Step 2: Rewrite the index tests for the new format**

In `test/playcode/export/static_site_search_test.exs`, add after the "shard keys and file names" test:

```elixir
  test "lines are chunked in the size the browser expects" do
    assert Search.lines_per_chunk() == cases()["lines_per_chunk"]
  end
```

Replace the first three tests inside `describe "the index files"` with:

```elixir
    test "a word's shard points at its line, and the line's chunk holds it as printed", %{
      play: play,
      dir: dir
    } do
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")

      {"lines", key, %{"speakers" => speakers, "lines" => lines}} =
        load_js!(dir, "search/lines/#{play.code}/0.js")

      assert key == "#{play.code}/0"
      line = Enum.find_index(lines, &(Enum.at(&1, 1) == "l12"))

      # Play 0, one line, delta line * 2 + flag 0.
      assert shard["sueño"] == [0, 1, line * 2]

      assert ["act-2", "l12", "II, 12", speaker, "v", "Decir que sueño es engaño"] =
               Enum.at(lines, line)

      assert Enum.at(speakers, speaker) == "Segismundo"
    end

    test "a stage direction is marked as one", %{dir: dir} do
      {"index", "va", shard} = load_js!(dir, "search/index/va.js")

      assert [0, 1, delta] = shard["vase"]
      assert rem(delta, 2) == 1
    end

    test "a word that starts with ñ lives in a shard named by its code point", %{dir: dir} do
      {"index", "ña", shard} = load_js!(dir, "search/index/u00f1a.js")

      assert Map.has_key?(shard, "ñaque")
    end
```

Add after the `describe` block:

```elixir
  test "a long play's lines are written in chunks of 100, each naming its own speakers" do
    verses = fn speaker, from, to ->
      lines = Enum.map_join(from..to, "", &~s(<l n="#{&1}">verso #{&1}</l>))
      "<sp><speaker>#{speaker}</speaker>#{lines}</sp>"
    end

    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            #{verses.("ANA", 1, 100)}#{verses.("JUAN", 101, 150)}
          </div1>
          """
        )
      )

    dir = generate!([play], all: true)

    {"lines", _, first} = load_js!(dir, "search/lines/#{play.code}/0.js")
    {"lines", _, second} = load_js!(dir, "search/lines/#{play.code}/1.js")
    refute File.exists?(Path.join([dir, "search", "lines", play.code, "2.js"]))

    assert {length(first["lines"]), first["speakers"]} == {100, ["ANA"]}
    assert {length(second["lines"]), second["speakers"]} == {50, ["JUAN"]}
    assert Enum.at(second["lines"], 0) |> Enum.at(1) == "l101"

    # "120" occurs only in verse 120, the 120th line (index 119): delta 119 * 2.
    {"index", "12", shard} = load_js!(dir, "search/index/12.js")
    assert shard["120"] == [0, 1, 238]
  end
```

In the test "adding a play to a generated site adds it to the index", replace the last assertion `assert length(shard["sueño"]) == 6` with:

```elixir
    # One line in play 0 and one in play 1.
    assert [0, 1, _, 1, 1, _] = shard["sueño"]
```

- [ ] **Step 3: Run them**

Run: `mix test test/playcode/export/static_site_search_test.exs`
Expected: FAIL — `Search.lines_per_chunk/0` is undefined; `search/lines/<CODE>/0.js` does not exist.

- [ ] **Step 4: Rewrite the writer half of `search.ex`**

Replace the moduledoc of `lib/playcode/export/static_site/search.ex` with:

```elixir
  @moduledoc """
  Full-text search for the static site: the normaliser, and the writer of the index
  files. Both are read in the browser by `priv/static_site/search.js`.

  Files are JS that call `EMOTHE.search.load/3`, not JSON, because browsers refuse
  `fetch` on `file://` while a `<script>` tag still works there:

    * `search/plays.js` — the plays in index order;
    * `search/index/<shard>.js` — word → postings, sharded by the word's first two
      characters. Per play, `[play, n, d1 … dn]`: `d = (line - previous line) * 2 + flag`,
      previous starting at 0, flag 1 for a stage direction;
    * `search/lines/<CODE>/<k>.js` — lines `k * 100` to `k * 100 + 99` of one play, so a
      search loads only the lines it shows.

  `normalise/1` and `words/1` must agree with `EMOTHE.normalise` and `EMOTHE.words` in
  `site.js`; `test/fixtures/search_normalisation.json` runs against both.
  """
```

Replace everything from `@kinds %{verse: "v", prose: "p", stage: "s"}` down to (not including) `defp play_entry(play) do` with:

```elixir
  @kinds %{verse: "v", prose: "p", stage: "s"}
  @lines_per_chunk 100

  @doc "Lines per `search/lines/<CODE>/<k>.js` file; `search.js` uses the same number."
  def lines_per_chunk, do: @lines_per_chunk

  @doc "The shard a word lives in: its first two characters (code points)."
  def shard_key(word), do: word |> String.codepoints() |> Enum.take(2) |> Enum.join()

  @doc "A shard key as a file name: `a-z` and `0-9` as they are, anything else as `u` + 4 hex digits."
  def shard_file(key) do
    key
    |> String.codepoints()
    |> Enum.map_join(fn char ->
      if char =~ ~r/\A[a-z0-9]\z/ do
        char
      else
        <<code::utf8>> = char
        "u" <> (code |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(4, "0"))
      end
    end)
  end

  @doc """
  Writes `search/lines/<CODE>/<k>.js` for one play and returns its postings:
  `%{word => [{line, flag}]}`, lines ascending, flag 1 for a stage direction.
  """
  def write_play(dir, %Edition{} = edition) do
    code = StaticSite.safe_code!(edition.play.code)
    play_dir = Path.join([dir, "search", "lines", code])
    File.rm_rf!(play_dir)

    entries =
      for item <- edition.items, Map.has_key?(edition.page_of, item.element.id) do
        %{
          slug: edition.page_of[item.element.id],
          anchor: edition.anchors[item.element.id],
          ref: edition.refs[item.element.id],
          speaker: speaker(item),
          kind: @kinds[item.kind],
          text: InlineMarkup.plain(item.element.content)
        }
      end

    entries
    |> Enum.chunk_every(@lines_per_chunk)
    |> Enum.with_index()
    |> Enum.each(fn {chunk, k} ->
      speakers = chunk |> Enum.map(& &1.speaker) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      index_of = speakers |> Enum.with_index() |> Map.new()

      lines =
        Enum.map(chunk, &[&1.slug, &1.anchor, &1.ref, index_of[&1.speaker], &1.kind, &1.text])

      write_js!(Path.join(play_dir, "#{k}.js"), "lines", "#{code}/#{k}", %{
        "speakers" => speakers,
        "lines" => lines
      })
    end)

    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, line} ->
      flag = if entry.kind == "s", do: 1, else: 0
      entry.text |> words() |> Enum.uniq() |> Enum.map(&{&1, {line, flag}})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp speaker(%{speakers: []}), do: nil
  defp speaker(%{speakers: speakers}), do: Enum.map_join(speakers, " / ", &elem(&1, 1))

  @doc """
  Writes `search/plays.js` and every shard for `plays`, in that order. `postings` maps a
  play's code to what `write_play/2` returned for it. Removes the lines files of plays
  that are no longer in `plays`. Returns the total and the largest shard size.
  """
  def write_index(dir, plays, postings) do
    write_js!(
      Path.join([dir, "search", "plays.js"]),
      "plays",
      "all",
      Enum.map(plays, &play_entry/1)
    )

    prune_lines(dir, plays)

    groups =
      for {play, p} <- Enum.with_index(plays),
          {word, lines} <- Map.get(postings, play.code, %{}),
          reduce: %{} do
        acc -> Map.update(acc, word, [{p, deltas(lines)}], &[{p, deltas(lines)} | &1])
      end

    write_shards(Path.join([dir, "search", "index"]), groups)
  end

  # `groups` maps a word to its `{play, deltas}` per play, in any order.
  defp write_shards(index_dir, groups) do
    File.rm_rf!(index_dir)
    File.mkdir_p!(index_dir)

    sizes =
      groups
      |> Enum.group_by(fn {word, _groups} -> shard_key(word) end)
      |> Enum.map(fn {key, words} ->
        data =
          Map.new(words, fn {word, play_groups} ->
            postings =
              play_groups
              |> Enum.sort()
              |> Enum.flat_map(fn {p, deltas} -> [p, length(deltas) | deltas] end)

            {word, postings}
          end)

        write_js!(Path.join(index_dir, shard_file(key) <> ".js"), "index", key, data)
      end)

    %{index_bytes: Enum.sum(sizes), largest_shard_bytes: Enum.max(sizes, fn -> 0 end)}
  end

  defp deltas(lines) do
    {deltas, _last} =
      Enum.map_reduce(lines, 0, fn {line, flag}, previous -> {(line - previous) * 2 + flag, line} end)

    deltas
  end

  # Anything under search/lines/ that is not the folder of a play in the site: a removed
  # play, or a lines file written by an older build.
  defp prune_lines(dir, plays) do
    lines_dir = Path.join([dir, "search", "lines"])
    keep = MapSet.new(plays, & &1.code)

    case File.ls(lines_dir) do
      {:ok, entries} ->
        for entry <- entries, not MapSet.member?(keep, entry),
            do: File.rm_rf!(Path.join(lines_dir, entry))

      {:error, _} ->
        :ok
    end
  end
```

- [ ] **Step 5: Pass postings by code from the orchestrator**

In `lib/playcode/export/static_site.ex`:

In `generate/1`, replace the `Map.put(write_play(edition, dir, site), :postings, Search.write_play(dir, edition, n - 1))` expression with:

```elixir
            edition
            |> write_play(dir, site)
            |> Map.merge(%{code: play.code, postings: Search.write_play(dir, edition)})
```

and replace `report = write_index_pages(plays, results, dir, opts)` with:

```elixir
        report = write_index_pages(plays, Map.new(results, &{&1.code, &1.postings}), dir, opts)
```

In `rebuild_index/1`, replace the `results = … |> Enum.map(fn {play, i} -> … end)` block and the `write_index_pages(plays, results, dir, opts)` line with:

```elixir
      postings = Map.new(plays, &{&1.code, Search.write_play(dir, Edition.load(&1.id))})
      write_index_pages(plays, postings, dir, opts)
```

In `write_index_pages/4`, rename the parameter `results` to `postings` and replace its last line with:

```elixir
    Search.write_index(dir, plays, postings)
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/playcode/export/static_site_search_test.exs`
Expected: PASS.

- [ ] **Step 7: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: all pass. (`search.js` still reads the old format until Task 2; no Elixir test runs it.)

```bash
git add lib/playcode/export/static_site/search.ex lib/playcode/export/static_site.ex test/fixtures/search_normalisation.json test/playcode/export/static_site_search_test.exs
git commit -m "feat: static search lines in 100-line chunks, postings delta-encoded

A first search loaded the whole lines file of twenty plays, about 4 MB on
the dev corpus; a chunk holds only the lines a result shows. Shards store
each play's lines as deltas, about half their old size.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `search.js` reads chunks and decodes postings

**Files:**
- Modify: `priv/static_site/search.js`
- Test: `test/js/search.test.mjs`

**Interfaces:**
- Consumes: the file formats of Task 1.
- Produces: `EMOTHE.search.LINES_PER_CHUNK`, `.decode(list) -> [[play, line, flag]]`, `.chunkKey(code, line) -> "<CODE>/<k>"`; `.hits` returns `{"play:line": flag}` from the new shard format. The search page shows ten plays first.

- [ ] **Step 1: Update the Node tests**

In `test/js/search.test.mjs`, replace the test "hits gather every matching word of a shard and keep the stage flag" with:

```js
test('hits gather every matching word of a shard and keep the stage flag', () => {
  // sueño: play 0, line 4, spoken; sueños: play 1, line 2, stage; suelo: play 0, line 9.
  const shard = { 'sueño': [0, 1, 8], 'sueños': [1, 1, 5], 'suelo': [0, 1, 18] };
  assert.deepEqual(plain(S.hits(shard, 'sueño', 'prefix')), { '0:4': 0, '1:2': 1 });
  assert.deepEqual(plain(S.hits(undefined, 'sueño', 'prefix')), {});
  assert.deepEqual(plain(S.intersect([{ '0:4': 0, '1:2': 1 }, { '0:4': 0 }])), { '0:4': 0 });
  assert.deepEqual(plain(S.intersect([])), {});
});

test('postings decode play by play from line deltas', () => {
  assert.deepEqual(plain(S.decode([0, 2, 8, 5, 3, 1, 0])), [[0, 4, 0], [0, 6, 1], [3, 0, 0]]);
  assert.deepEqual(plain(S.decode([])), []);
});

test('a line is looked up in the chunk the build wrote it to', () => {
  assert.equal(S.LINES_PER_CHUNK, cases.lines_per_chunk);
  assert.equal(S.chunkKey('EMOTHE0001', 0), 'EMOTHE0001/0');
  assert.equal(S.chunkKey('EMOTHE0001', 99), 'EMOTHE0001/0');
  assert.equal(S.chunkKey('EMOTHE0001', 100), 'EMOTHE0001/1');
});
```

- [ ] **Step 2: Run them**

Run: `node --test test/js/search.test.mjs`
Expected: FAIL — `S.decode is not a function`; the hits test returns `{}`.

- [ ] **Step 3: Replace `priv/static_site/search.js`**

```js
/* EMOTHE static edition: full-text search over the files StaticSite.Search writes.
   Loaded only by search.html, after site.js (EMOTHE.normalise, EMOTHE.words). */
(function (root) {
  'use strict';
  var E = root.EMOTHE = root.EMOTHE || {};
  var S = E.search = E.search || {};
  var store = { plays: null, index: {}, lines: {} };
  var waiting = {};

  // Must match Playcode.Export.StaticSite.Search.lines_per_chunk/0.
  S.LINES_PER_CHUNK = 100;

  S.load = function (kind, key, value) {
    if (kind === 'plays') store.plays = value; else store[kind][key] = value;
    var id = kind + ':' + key, callbacks = waiting[id] || [];
    delete waiting[id];
    callbacks.forEach(function (resolve) { resolve(); });
  };

  S.shardKey = function (word) { return Array.from(word).slice(0, 2).join(''); };

  S.shardFile = function (key) {
    return Array.from(key).map(function (c) {
      return /^[a-z0-9]$/.test(c) ? c : 'u' + c.codePointAt(0).toString(16).padStart(4, '0');
    }).join('');
  };

  S.chunkKey = function (code, line) { return code + '/' + Math.floor(line / S.LINES_PER_CHUNK); };

  // [play, n, d1 … dn, play, n, …], d = (line - previous line) * 2 + flag  →  [[play, line, flag]]
  S.decode = function (list) {
    var out = [];
    for (var i = 0; i < list.length; i += 2 + list[i + 1]) {
      var line = 0;
      for (var j = 0; j < list[i + 1]; j++) {
        var d = list[i + 2 + j];
        line += Math.floor(d / 2);
        out.push([list[i], line, d % 2]);
      }
    }
    return out;
  };

  // Words in quotes are a phrase; every word, in a phrase or not, must occur in the line.
  S.parse = function (query) {
    var phrases = [];
    var rest = String(query || '').replace(/"([^"]*)"/g, function (_, inner) {
      var words = E.words(inner);
      if (words.length) phrases.push(words);
      return ' ';
    });
    var all = E.words(rest);
    phrases.forEach(function (phrase) { all = all.concat(phrase); });
    return { words: all.filter(function (w, i) { return all.indexOf(w) === i; }), phrases: phrases };
  };

  // A one-letter word has a shard of its own, so it can only match whole.
  S.matches = function (token, word, mode) {
    return mode === 'prefix' && Array.from(word).length > 1 ? token.indexOf(word) === 0 : token === word;
  };

  S.hasPhrase = function (tokens, phrase, mode) {
    for (var i = 0; i + phrase.length <= tokens.length; i++) {
      var ok = true;
      for (var j = 0; j < phrase.length && ok; j++) ok = S.matches(tokens[i + j], phrase[j], mode);
      if (ok) return true;
    }
    return false;
  };

  // Hits for one word: {"play:line": 1 for a stage direction, 0 for spoken text}.
  S.hits = function (shard, word, mode) {
    var hits = {};
    Object.keys(shard || {}).forEach(function (token) {
      if (!S.matches(token, word, mode)) return;
      S.decode(shard[token]).forEach(function (h) { hits[h[0] + ':' + h[1]] = h[2]; });
    });
    return hits;
  };

  S.intersect = function (maps) {
    var out = {};
    if (!maps.length) return out;
    Object.keys(maps[0]).forEach(function (k) {
      if (maps.every(function (m) { return k in m; })) out[k] = maps[0][k];
    });
    return out;
  };

  if (!root.document) return;

  var FIRST_PLAYS = 10, FIRST_LINES = 5;
  var form, results, count, facetsEl, state = null, renders = 0, runs = 0;
  var FACETS = [
    ['language', 'Language', function (play) { return play.language_name; }],
    ['author', 'Author', function (play) { return play.author || '—'; }],
    ['kind', 'Kind', function (play) { return play.kind === 'original' ? 'Originals' : 'Translations'; }],
    ['type', 'Text', function (play, stage) { return stage ? 'Stage directions' : 'Spoken'; }]
  ];

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function button(label, onClick) {
    var b = el('button', 'more', label);
    b.type = 'button';
    b.addEventListener('click', onClick);
    return b;
  }

  // Loads a search file once; a missing file (a word with no shard) loads as empty.
  function need(kind, key, src) {
    var have = kind === 'plays' ? store.plays : store[kind][key];
    if (have) return Promise.resolve();
    var id = kind + ':' + key;
    return new Promise(function (resolve) {
      if (waiting[id]) { waiting[id].push(resolve); return; }
      waiting[id] = [resolve];
      var script = document.createElement('script');
      script.src = src;
      script.onerror = function () { S.load(kind, key, kind === 'index' ? {} : kind === 'plays' ? [] : { speakers: [], lines: [] }); };
      document.head.appendChild(script);
    });
  }

  // Loads the chunks holding the given [play, line] pairs.
  function loadLines(pairs) {
    var keys = {};
    pairs.forEach(function (pl) { keys[S.chunkKey(store.plays[pl[0]].code, pl[1])] = true; });
    return Promise.all(Object.keys(keys).map(function (key) {
      return need('lines', key, 'search/lines/' + key + '.js');
    }));
  }

  // A line and its chunk, or null when the chunk could not be loaded.
  function lineOf(p, l) {
    var chunk = store.lines[S.chunkKey(store.plays[p].code, l)];
    var row = chunk && chunk.lines[l % S.LINES_PER_CHUNK];
    return row ? { row: row, speakers: chunk.speakers } : null;
  }

  function pairsOf(hits) {
    return Object.keys(hits).map(function (k) { return k.split(':').map(Number); });
  }

  function phraseFilter(hits, phrases, mode) {
    var out = {};
    pairsOf(hits).forEach(function (pl) {
      var line = lineOf(pl[0], pl[1]);
      if (line && phrases.every(function (p) { return S.hasPhrase(E.words(line.row[5]), p, mode); })) {
        out[pl[0] + ':' + pl[1]] = hits[pl[0] + ':' + pl[1]];
      }
    });
    return out;
  }

  function run() {
    var query = form.elements.q.value, mode = form.elements.mode.value;
    var my = ++runs;
    try { root.history.replaceState(null, '', '?' + new URLSearchParams({ q: query, mode: mode }).toString()); } catch (e) { /* file:// may refuse */ }
    var parsed = S.parse(query);
    if (!parsed.words.length) { state = null; render(); return; }
    var keys = parsed.words.map(S.shardKey).filter(function (k, i, a) { return a.indexOf(k) === i; });
    count.textContent = 'Searching…';
    need('plays', 'all', 'search/plays.js')
      .then(function () {
        return Promise.all(keys.map(function (k) { return need('index', k, 'search/index/' + S.shardFile(k) + '.js'); }));
      })
      .then(function () {
        var hits = S.intersect(parsed.words.map(function (w) { return S.hits(store.index[S.shardKey(w)], w, mode); }));
        if (!parsed.phrases.length) return hits;
        // A phrase is checked against the text, so its candidate lines' chunks are loaded.
        return loadLines(pairsOf(hits)).then(function () { return phraseFilter(hits, parsed.phrases, mode); });
      })
      .then(function (hits) {
        if (my !== runs) return;
        state = { hits: hits, words: parsed.words, mode: mode, open: {}, filters: {}, allPlays: false };
        render();
      });
  }

  function passes(play, stage, skip) {
    return FACETS.every(function (f) {
      var want = state.filters[f[0]];
      return f === skip || !want || f[2](play, stage) === want;
    });
  }

  function render() {
    var token = ++renders;
    results.textContent = '';
    facetsEl.textContent = '';
    if (!state) { count.textContent = ''; return; }

    var groups = {};
    Object.keys(state.hits).forEach(function (k) {
      var pl = k.split(':').map(Number);
      if (passes(store.plays[pl[0]], state.hits[k] === 1)) (groups[pl[0]] = groups[pl[0]] || []).push(pl[1]);
    });
    var order = Object.keys(groups).map(Number).sort(function (a, b) {
      return groups[b].length - groups[a].length || store.plays[a].title.localeCompare(store.plays[b].title);
    });
    var total = order.reduce(function (n, p) { return n + groups[p].length; }, 0);
    count.textContent = total + (total === 1 ? ' line' : ' lines') + ' in ' + order.length + (order.length === 1 ? ' play' : ' plays');
    renderFacets();

    var shown = state.allPlays ? order : order.slice(0, FIRST_PLAYS);
    var visible = {}, pairs = [];
    shown.forEach(function (p) {
      var lines = groups[p].sort(function (a, b) { return a - b; });
      visible[p] = state.open[p] ? lines : lines.slice(0, FIRST_LINES);
      visible[p].forEach(function (l) { pairs.push([p, l]); });
    });
    loadLines(pairs).then(function () {
      if (token !== renders) return;
      shown.forEach(function (p) { results.appendChild(group(p, groups[p].length, visible[p])); });
      if (order.length > shown.length) {
        results.appendChild(button('Show all ' + order.length + ' plays', function () { state.allPlays = true; render(); }));
      }
    });
  }

  function renderFacets() {
    FACETS.forEach(function (f) {
      var counts = {};
      Object.keys(state.hits).forEach(function (k) {
        var p = Number(k.split(':')[0]), stage = state.hits[k] === 1, play = store.plays[p];
        if (passes(play, stage, f)) { var v = f[2](play, stage); counts[v] = (counts[v] || 0) + 1; }
      });
      var values = Object.keys(counts).sort(function (a, b) { return counts[b] - counts[a]; });
      if (values.length < 2 && !state.filters[f[0]]) return;
      var fieldset = el('fieldset', 'facet');
      fieldset.appendChild(el('legend', null, f[1]));
      [''].concat(values).forEach(function (v) {
        var label = el('label'), input = el('input');
        input.type = 'radio';
        input.name = 'facet-' + f[0];
        input.value = v;
        input.checked = (state.filters[f[0]] || '') === v;
        input.addEventListener('change', function () { state.filters[f[0]] = v; state.open = {}; render(); });
        label.appendChild(input);
        label.appendChild(el('span', null, v || 'All'));
        label.appendChild(el('span', 'count', v ? String(counts[v]) : ''));
        fieldset.appendChild(label);
      });
      facetsEl.appendChild(fieldset);
    });
  }

  function group(p, total, lines) {
    var play = store.plays[p];
    var section = el('section', 'group'), heading = el('h2'), link = el('a', null, play.title);
    link.href = 'plays/' + play.code + '/index.html';
    heading.appendChild(link);
    section.appendChild(heading);
    var meta = [play.author, play.kind === 'translation' ? 'translation' : null, total + (total === 1 ? ' line' : ' lines')];
    section.appendChild(el('p', 'group-meta', meta.filter(Boolean).join(' · ')));
    var list = el('ol', 'hits');
    lines.forEach(function (l) {
      var line = lineOf(p, l);
      if (line) list.appendChild(hit(play, line));
    });
    section.appendChild(list);
    if (total > lines.length) section.appendChild(button('Show all ' + total, function () { state.open[p] = true; render(); }));
    return section;
  }

  function hit(play, line) {
    var row = line.row, li = el('li', 'hit'), ref = el('a', 'ref', row[2]);
    ref.href = 'plays/' + play.code + '/' + row[0] + '.html#' + row[1];
    li.appendChild(ref);
    li.appendChild(el('span', 'spk', row[3] === null ? '' : line.speakers[row[3]]));
    var text = el('span', row[4] === 's' ? 'line stage' : 'line');
    highlight(text, row[5]);
    li.appendChild(text);
    return li;
  }

  // Built with text nodes, never innerHTML: the line text is data.
  function highlight(target, text) {
    text.split(/([\p{L}\p{M}\p{N}]+)/u).forEach(function (part, i) {
      var word = i % 2 === 1 && E.normalise(part);
      if (word && state.words.some(function (w) { return S.matches(word, w, state.mode); })) {
        target.appendChild(el('mark', null, part));
      } else if (part) {
        target.appendChild(document.createTextNode(part));
      }
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    form = document.querySelector('[data-search-form]');
    if (!form) return;
    results = document.querySelector('[data-search-results]');
    count = document.querySelector('[data-search-count]');
    facetsEl = document.querySelector('[data-search-facets]');
    form.hidden = false;
    var params = new URLSearchParams(root.location.search);
    form.elements.q.value = params.get('q') || '';
    if (params.get('mode') === 'word') form.elements.mode.value = 'word';
    form.addEventListener('submit', function (event) { event.preventDefault(); run(); });
    if (form.elements.q.value) run();
  });
})(typeof window !== 'undefined' ? window : globalThis);
```

- [ ] **Step 4: Run the tests**

Run: `node --test test/js/search.test.mjs`
Expected: PASS (9 tests).

- [ ] **Step 5: Check it in a browser, headless**

Run `mix playcode.export.site --all -o <scratchpad>/site`. With headless Chrome, `--dump-dom --virtual-time-budget=10000` on `file://<scratchpad>/site/search.html?q=sueño&mode=prefix`, `?q=%22la%20vida%20es%22`, `?q=y` and `?q=%C2%BF%C2%A1`: the first three render a count line, groups with `<mark>`, at most ten groups before a "Show all" button; the last renders nothing and throws nothing. Record in the report how many `search/lines/**/*.js` scripts each page added to `<head>` (count the `<script src="search/lines/` entries in the dumped DOM). Clicks on facets and "Show all" stay for a human.

- [ ] **Step 6: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test && node --test test/js/search.test.mjs`
Expected: all pass; `wc -c priv/static_site/search.js` ≤ 15,000.

```bash
git add priv/static_site/search.js test/js/search.test.mjs
git commit -m "feat: search page loads only the chunks it shows, ten plays first

Postings are decoded from line deltas; a result group loads the chunks
holding its first five lines, and the page starts with ten groups.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Parallel builds, an incremental index, work-family pages that follow

**Files:**
- Modify: `lib/playcode/export/static_site/search.ex`, `lib/playcode/export/static_site.ex`
- Test: `test/playcode/export/static_site_search_test.exs`, `test/playcode/export/static_site_test.exs`

**Interfaces:**
- Consumes: `Search.write_play/2`, `Search.write_index/3` (Task 1).
- Produces: `Search.write_index(dir, plays, postings)` now carries over, from the shards on disk, every play in `plays` that `postings` lacks; `Search.indexed_codes(dir) :: [code]` (empty when the index predates chunked lines); `StaticSite.rebuild_index(opts \\ [], postings \\ %{})`.

- [ ] **Step 1: Write the tests**

Append to `test/playcode/export/static_site_search_test.exs`:

```elixir
  describe "updating a generated site" do
    setup do
      play = fn word ->
        import_tei!(
          tei(
            body:
              ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">sueño #{word}</l></sp></div1>)
          )
        )
      end

      %{first: play.("primero"), second: play.("segundo")}
    end

    test "adding a play leaves the others' search entries as they were last generated",
         %{first: first, second: second} do
      dir = generate!([first], all: true)

      # Change the first play after the site was built: adding the second must not
      # reload it, so its entries still say "primero".
      [line] = for d <- Playcode.PlayContent.load_play_content(first.id), el <- d.loaded_elements,
                   %{type: "verse_line"} = l <- el.children, do: l

      {:ok, _} = Playcode.PlayContent.update_element(line, %{content: "nada"})

      :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

      {"index", "pr", shard} = load_js!(dir, "search/index/pr.js")
      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      first_index = Enum.find_index(plays, &(&1["code"] == first.code))

      assert [^first_index, 1, _] = shard["primero"]
      refute File.exists?(Path.join([dir, "search", "index", "na.js"]))
    end

    test "removing a play takes its lines and its words out of the index",
         %{first: first, second: second} do
      dir = generate!([first, second], all: true)

      :ok = Playcode.Export.StaticSite.remove_single_play(second.code, output_dir: dir)

      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")

      assert Enum.map(plays, & &1["code"]) == [first.code]
      assert shard["sueño"] == [0, 1, 0]
      refute File.exists?(Path.join([dir, "search", "index", "se.js"]))
      refute File.exists?(Path.join([dir, "search", "lines", second.code]))
    end

    test "removing the last play leaves an empty site that still builds", %{first: first} do
      dir = generate!([first], all: true)

      :ok = Playcode.Export.StaticSite.remove_single_play(first.code, output_dir: dir)

      assert {"plays", "all", []} = load_js!(dir, "search/plays.js")
      assert Path.wildcard(Path.join([dir, "search", "index", "*.js"])) == []
      assert read!(dir, "index.html") =~ "0 plays"
    end

    test "a site whose index predates chunked lines is re-indexed in full",
         %{first: first, second: second} do
      dir = generate!([first], all: true)

      # What a build before chunked lines left: a lines file, not a folder.
      File.rm_rf!(Path.join([dir, "search", "lines", first.code]))
      File.write!(Path.join([dir, "search", "lines", "#{first.code}.js"]), "old")

      :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

      {"index", "su", shard} = load_js!(dir, "search/index/su.js")
      assert [0, 1, 0, 1, 1, 0] = shard["sueño"]
      assert File.exists?(Path.join([dir, "search", "lines", first.code, "0.js"]))
      refute File.exists?(Path.join([dir, "search", "lines", "#{first.code}.js"]))
    end
  end
```

Before writing it, check the names it uses: `Playcode.PlayContent.update_element/2` (grep `def update_element` in `lib/playcode/play_content.ex`) and the shape of `load_play_content/1` (speech elements under `loaded_elements`, verse lines under `children`, possibly under a line group — adapt the comprehension so it finds the one verse line, and say so in the report if you change it).

Append to `test/playcode/export/static_site_test.exs`:

```elixir
  test "adding or removing a translation updates its original's title page" do
    %{original: original, translation: translation} = translation_family_fixture()
    dir = generate!([original])
    link = "../#{translation.code}/index.html"

    :ok = StaticSite.generate_single_play(translation.id, output_dir: dir)
    assert link in hrefs(title_page(dir, original))

    :ok = StaticSite.remove_single_play(translation.code, output_dir: dir)
    refute link in hrefs(title_page(dir, original))
  end
```

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export/static_site_search_test.exs test/playcode/export/static_site_test.exs`
Expected: FAIL — "adding a play leaves the others' search entries…" finds `"nada"` indexed (the rebuild reloads every play); the work-family test fails (the original's title page is not rewritten).

- [ ] **Step 3: Carry postings over in `Search.write_index/3`**

In `lib/playcode/export/static_site/search.ex`, replace `write_index/3` and add the helpers:

```elixir
  @doc """
  Writes `search/plays.js` and every shard for `plays`, in that order. `postings` maps a
  play's code to what `write_play/2` returned for it; a play in `plays` that `postings`
  lacks keeps the postings the site's current shards hold for it, under its new index, so
  adding or removing one play reloads no other. Removes the lines files of plays no longer
  in `plays`. Returns the total and the largest shard size.
  """
  def write_index(dir, plays, postings) do
    index_dir = Path.join([dir, "search", "index"])
    order = plays |> Enum.with_index() |> Map.new(fn {play, p} -> {play.code, p} end)

    # Read before plays.js is rewritten: it maps the old shards' play numbers to codes.
    carried = carried_groups(dir, index_dir, order, postings)

    write_js!(
      Path.join([dir, "search", "plays.js"]),
      "plays",
      "all",
      Enum.map(plays, &play_entry/1)
    )

    prune_lines(dir, plays)

    groups =
      for {code, by_word} <- postings,
          p when not is_nil(p) <- [order[code]],
          {word, lines} <- by_word,
          reduce: carried do
        acc -> Map.update(acc, word, [{p, deltas(lines)}], &[{p, deltas(lines)} | &1])
      end

    write_shards(index_dir, groups)
  end

  @doc """
  Codes of the plays the site's current index holds, in index order. Empty when the index
  predates chunked lines (some play has no `search/lines/<CODE>/` folder): its shards are
  in another format and must not be carried over.
  """
  def indexed_codes(dir) do
    with {:ok, plays} <- read_js(Path.join([dir, "search", "plays.js"])),
         codes = Enum.map(plays, & &1["code"]),
         true <- Enum.all?(codes, &File.dir?(Path.join([dir, "search", "lines", &1]))) do
      codes
    else
      _ -> []
    end
  end

  # Every word's postings in the current shards as `{new play index, deltas}`: a play's
  # deltas do not change when its index does. Plays that left the site, and plays whose
  # postings were just recomputed, are dropped.
  defp carried_groups(dir, index_dir, order, postings) do
    remap =
      dir
      |> indexed_codes()
      |> Enum.with_index()
      |> Map.new(fn {code, old} ->
        {old, if(Map.has_key?(postings, code), do: nil, else: order[code])}
      end)

    if remap == %{} do
      %{}
    else
      for path <- Path.wildcard(Path.join(index_dir, "*.js")),
          {:ok, shard} <- [read_js(path)],
          {word, list} <- shard,
          {old, deltas} <- play_groups(list),
          new when not is_nil(new) <- [remap[old]],
          reduce: %{} do
        acc -> Map.update(acc, word, [{new, deltas}], &[{new, deltas} | &1])
      end
    end
  end

  defp play_groups([]), do: []

  defp play_groups([play, n | rest]) do
    {deltas, rest} = Enum.split(rest, n)
    [{play, deltas} | play_groups(rest)]
  end

  defp read_js(path) do
    with {:ok, js} <- File.read(path),
         [_, json] <- Regex.run(~r/\AEMOTHE\.search\.load\(".*?",".*?",(.*)\);\n\z/s, js) do
      {:ok, Jason.decode!(json)}
    else
      _ -> :error
    end
  end
```

- [ ] **Step 4: Parallel generate, incremental rebuild, family pages**

In `lib/playcode/export/static_site.ex`:

Replace the `results = plays |> Enum.with_index(1) |> Enum.map(…)` block in `generate/1` with:

```elixir
        results =
          plays
          |> Task.async_stream(&build_play(&1.id, dir, site),
            max_concurrency: concurrency(),
            timeout: :infinity
          )
          |> Enum.with_index(1)
          |> Enum.map(fn {{:ok, result}, n} ->
            opts[:on_progress].(%{step: :play, current: n, total: total, detail: result.code})
            result
          end)
```

Replace `generate_single_play/2`, `remove_single_play/2` and `rebuild_index/1` with:

```elixir
  @doc "Exports one play into an existing site, then rebuilds the catalogue and index."
  def generate_single_play(play_id, opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      File.mkdir_p!(Path.join(dir, "plays"))

      edition = Edition.load(play_id)
      site = site(opts, MapSet.new([edition.play.code | list_exported_codes(dir)]))
      write_play(edition, dir, site)
      refresh_family(edition.play, dir, site)
      rebuild_index(opts, %{edition.play.code => Search.write_play(dir, edition)})
      :ok
    end)
  end

  @doc "Removes one play from an existing site, then rebuilds the catalogue and index."
  def remove_single_play(code, opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]

      if code in list_exported_codes(dir) do
        safe_code!(code)
        File.rm_rf!(Path.join([dir, "plays", code]))
        File.rm(Path.join([dir, "plays", "#{code}.html"]))

        with %Play{} = play <- Enum.find(Catalogue.list_plays(include_deleted: true), &(&1.code == code)) do
          refresh_family(play, dir, site(opts, MapSet.new(list_exported_codes(dir))))
        end
      end

      rebuild_index(opts)
      :ok
    end)
  end

  @doc """
  Rewrites the catalogue, about and search pages and the search index for the plays on
  disk. `postings` holds freshly computed postings by code; every other play keeps what
  the current index holds for it, and a play the index lacks is loaded and indexed.
  """
  def rebuild_index(opts \\ [], postings \\ %{}) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      codes = list_exported_codes(dir)
      plays = Catalogue.list_plays(sort: :title_sort) |> Enum.filter(&(&1.code in codes))
      indexed = MapSet.new(Search.indexed_codes(dir))

      missing =
        plays
        |> Enum.reject(&(Map.has_key?(postings, &1.code) or MapSet.member?(indexed, &1.code)))
        |> Task.async_stream(
          &{&1.code, Search.write_play(dir, Edition.load(&1.id))},
          max_concurrency: concurrency(),
          timeout: :infinity
        )
        |> Map.new(fn {:ok, pair} -> pair end)

      File.mkdir_p!(dir)
      write_assets(dir)
      write_index_pages(plays, Map.merge(postings, missing), dir, opts)
    end)
  end
```

Add, after `defp write_assets/1`:

```elixir
  # Prepares, writes and indexes one play; generate/1 runs several at once.
  defp build_play(play_id, dir, site) do
    edition = Edition.load(play_id)

    edition
    |> write_play(dir, site)
    |> Map.merge(%{code: edition.play.code, postings: Search.write_play(dir, edition)})
  end

  # Each play holds a database connection while it loads; two stay free for the app.
  defp concurrency do
    pool = Playcode.Repo.config()[:pool_size] || 10
    max(1, min(System.schedulers_online(), pool - 2))
  end

  # A title page links the play's published original and translations, so theirs change
  # when one of them is added or removed.
  defp refresh_family(play, dir, site) do
    exported = MapSet.new(list_exported_codes(dir))

    Catalogue.list_plays()
    |> Enum.filter(fn member ->
      (member.id == play.parent_play_id or member.parent_play_id == play.id) and
        MapSet.member?(exported, member.code)
    end)
    |> Enum.each(&(&1.id |> Edition.load() |> write_title_page(dir, site)))
  end

  defp write_title_page(%Edition{play: play} = edition, dir, site) do
    code = safe_code!(play.code)
    html = Pages.render(:title, %{edition: edition, site: site})
    File.write!(Path.join([dir, "plays", code, "index.html"]), html)
  end
```

In `write_play/3`, replace the line that writes `index.html` (`File.write!(Path.join(play_dir, "index.html"), Pages.render(:title, assigns))`) with `write_title_page(edition, dir, site)`.

Check `Catalogue.list_plays/1` honours `include_deleted: true` (its `scope/2`); `remove_single_play/2` needs it so a play archived after it was published can still be found.

- [ ] **Step 5: Run the tests**

Run: `mix test test/playcode/export`
Expected: PASS.

- [ ] **Step 6: Measure, run everything, commit**

Time the full dev corpus before and after: `time mix playcode.export.site --all -o <scratchpad>/site` (the baseline in the spec is 23 s sequential). Then, on that site, time one add: `mix run -e 'Playcode.Export.StaticSite.remove_single_play("EMOTHE0020_LaVidaEsSueno", output_dir: "<scratchpad>/site")'` and the matching `generate_single_play/2` with that play's id (use the code as it is in your dev DB). Record the three times in the report.

Run: `mix format && mix compile --warnings-as-errors && mix test`

```bash
git add lib/playcode/export/static_site/search.ex lib/playcode/export/static_site.ex test/playcode/export/static_site_search_test.exs test/playcode/export/static_site_test.exs
git commit -m "feat: parallel static builds and an incremental search index

generate/1 builds plays concurrently. Adding or removing one play reads
every other play's postings from the shards on disk instead of reloading
the corpus, re-indexing in full only an index older than chunked lines.
The original's and translations' title pages follow an add or remove.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Switching a play off no longer freezes the admin page

**Files:**
- Modify: `lib/playcode_web/live/admin/export_site_live.ex`
- Test: `test/playcode_web/live/admin/export_site_live_test.exs`

**Interfaces:**
- Consumes: `StaticSite.remove_single_play/2` (Task 3).
- Produces: a `:removing_play` assign (the play id being removed, or nil) and a `{:play_removed, code}` message.

- [ ] **Step 1: Update the test**

In `test/playcode_web/live/admin/export_site_live_test.exs`, in "switching a play on puts it in the site straight away; off takes it out", replace

```elixir
    assert lv |> element(switch(a)) |> render_click() =~
             t("Removed %{code} from static site.", code: a.code)
```

with

```elixir
    # Removing rebuilds the index, so it runs in a task like adding does.
    lv |> element(switch(a)) |> render_click()
    wait_for(fn -> render(lv) =~ t("Removed %{code} from static site.", code: a.code) end)
```

and add, at the end of that test, that the switch is usable again once the play is out:

```elixir
    refute has_element?(lv, "#{switch(a)}[disabled]")
```

**This task has no test that fails first, and that is deliberate.** Whether the removal runs in the LiveView's process or in a task is not observable without a race: the task may finish before the test reads the page, and a test that reads "busy" in between would pass or fail by timing. The updated test pins what a user sees — the play goes out, the flash says so, the switch works again — and passes before and after. Prove the change by hand instead (Step 5).

- [ ] **Step 2: Run the updated test on today's code**

Run: `mix test test/playcode_web/live/admin/export_site_live_test.exs`
Expected: PASS (the removal is synchronous today, so `wait_for` succeeds at once).

- [ ] **Step 3: Remove in a task**

In `lib/playcode_web/live/admin/export_site_live.ex`:

- In `mount/3`, add `|> assign(:removing_play, nil)` after `|> assign(:exporting_play, nil)`.
- Replace the guard clause of `handle_event("toggle_play", …)` with:

```elixir
  # One build at a time: adding or removing a play rewrites the shared catalogue and index.
  def handle_event("toggle_play", _params, socket)
      when socket.assigns.generating or not is_nil(socket.assigns.exporting_play) or
             not is_nil(socket.assigns.removing_play),
      do: {:noreply, socket}
```

- In the main `toggle_play` clause, replace the removal branch (`StaticSite.remove_single_play(code, opts)` and the `{:noreply, …}` after it) with:

```elixir
      lv = self()

      Task.start(fn ->
        StaticSite.remove_single_play(code, opts)
        send(lv, {:play_removed, code})
      end)

      {:noreply, assign(socket, :removing_play, id)}
```

- Add after `handle_info({:play_exported, _id}, socket)`:

```elixir
  def handle_info({:play_removed, code}, socket) do
    {:noreply,
     socket
     |> assign(
       :exported_codes,
       MapSet.new(StaticSite.list_exported_codes(StaticSite.output_dir()))
     )
     |> assign(:removing_play, nil)
     |> put_flash(:info, gettext("Removed %{code} from static site.", code: code))}
  end
```

- In the template: the Generate button's `disabled={@generating || @deploying || @exporting_play}` becomes `disabled={@generating || @deploying || @exporting_play || @removing_play}`; the spinner's `:if={@exporting_play == play.id}` becomes `:if={play.id in [@exporting_play, @removing_play]}`; the switch's `checked` and `disabled` become

```heex
                checked={
                  (MapSet.member?(@exported_codes, play.code) or @exporting_play == play.id) and
                    @removing_play != play.id
                }
                disabled={@generating || @exporting_play || @removing_play}
```

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode_web/live/admin/export_site_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Check it by hand, run everything and commit**

With `mix phx.server` and a site generated from the dev DB into the admin's output directory (`--all`), switch a play off on `/admin/export`: before this task the page stops responding for the whole rebuild; after it, the switch goes off and disabled at once, a spinner shows, and the flash arrives when the play is out. Say in the report what you saw, or that you could not run a browser.

Run: `mix format && mix compile --warnings-as-errors && mix test`

```bash
git add lib/playcode_web/live/admin/export_site_live.ex test/playcode_web/live/admin/export_site_live_test.exs
git commit -m "fix: switching a play off the site no longer freezes the admin page

Removal rebuilt the search index inside the LiveView's process; it now
runs in a task like adding does, with the switch off and disabled until
the play is out.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: A page per scene for a very long division

**Files:**
- Modify: `lib/playcode/export/static_site/edition.ex`, `lib/playcode/export/static_site/components.ex`
- Modify: `lib/playcode/export/static_site/pages/division.html.heex`, `pages/text.html.heex`
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Produces: pages are `%{slug, title, division, scene, split}` — `scene` is nil except on a scene page; `split` is true on the own page of a division that has scene pages. `Edition.scene_page(edition, scene) :: page | nil`, `Edition.scene_title(scene) :: String.t()`. `Components.page_text/1` (attrs `edition`, `page`).

- [ ] **Step 1: Write the tests**

Add two helpers beside the module's existing `page/3` and `ids/1` (functions do not go inside a `describe`):

```elixir
  defp next(html),
    do: html |> LazyHTML.query(~s(a[rel="next"])) |> LazyHTML.attribute("href") |> Enum.uniq()

  defp links(html), do: html |> LazyHTML.query("main a") |> LazyHTML.attribute("href")
```

Then append inside `Playcode.Export.StaticSitePlayTest`:

```elixir
  describe "a division too long for one page" do
    setup do
      # 72,000 bytes of text per scene: 144,000 in the act, over the 120,000 threshold.
      words = String.duplicate("palabra ", 9_000)

      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <stage>Salen todos</stage>
          <div2 type="escena" n="1"><head>Escena 1</head><sp><speaker>A</speaker><p>#{words}uno</p></sp></div2>
          <div2 type="escena" n="2"><head>Escena 2</head><sp><speaker>B</speaker><p>#{words}dos</p></sp></div2>
        </div1>
        <div1 type="acto" n="2"><head>Acto II</head><sp><speaker>A</speaker><p>fin</p></sp></div1>
        """)

      %{play: play, dir: dir}
    end

    test "gets a page per scene, walked in order", %{play: play, dir: dir} do
      act = page(dir, play, "act-1.html")

      assert LazyHTML.text(act) =~ "Salen todos"
      refute LazyHTML.text(act) =~ "palabra"
      assert "act-1-s1.html" in links(act)
      assert "act-1-s2.html" in links(act)

      assert next(act) == ["act-1-s1.html"]
      assert next(page(dir, play, "act-1-s1.html")) == ["act-1-s2.html"]
      assert next(page(dir, play, "act-1-s2.html")) == ["act-2.html"]

      second = LazyHTML.text(page(dir, play, "act-1-s2.html"))
      assert second =~ "palabra dos"
      refute second =~ "palabra uno"
    end

    test "the full text still holds every scene", %{play: play, dir: dir} do
      text = read!(dir, "plays/#{play.code}/text.html")

      assert text =~ "palabra uno"
      assert text =~ "palabra dos"
    end

    test "a search result lands on the scene's page", %{play: play, dir: dir} do
      {"lines", _, %{"lines" => lines}} = load_js!(dir, "search/lines/#{play.code}/0.js")

      assert ["act-1-s2" | _] = Enum.find(lines, &String.ends_with?(Enum.at(&1, 5), "dos"))
    end
  end
```

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: FAIL — `act-1-s1.html` does not exist (`File.Error`).

- [ ] **Step 3: Scene pages in `Edition`**

In `lib/playcode/export/static_site/edition.ex`:

In `load/1`, replace `pages = pages(divisions)` with `pages = pages(divisions, items)`.

Replace `defp pages/1` with:

```elixir
  # A division with more text than this gets a page per scene too, so that no act page
  # outgrows its 80 KB (gzipped) budget: on the dev corpus the largest pages that fit hold
  # 71 KB of text; the three that did not, 200–218 KB.
  @split_bytes 120_000

  # Every top-level division with text gets a page: acts are act-N by their ordinal
  # among all acts, as in the statistics; anything else is named by its type, with
  # -2, -3 for repeats. The cast list goes on the title page. A division over
  # @split_bytes with two or more scenes also gets a page per scene, after its own.
  defp pages(divisions, items) do
    bytes =
      Enum.reduce(items, %{}, fn item, acc ->
        Map.update(acc, item.division.id, text_bytes(item), &(&1 + text_bytes(item)))
      end)

    {pages, _counts} =
      Enum.map_reduce(divisions, %{}, fn division, counts ->
        base = if division.type in Metrics.act_types(), do: "act", else: division.type
        n = Map.get(counts, base, 0) + 1
        slug = if base == "act" or n > 1, do: "#{base}-#{n}", else: base
        title = division.title || String.capitalize(division.type)
        page = %{slug: slug, title: title, division: division, scene: nil, split: false}
        {page, Map.put(counts, base, n)}
      end)

    pages
    |> Enum.reject(&(&1.division.type == "elenco" or empty?(&1.division)))
    |> Enum.flat_map(fn page ->
      scenes = Enum.reject(page.division.children, &(&1.loaded_elements == []))

      if Map.get(bytes, page.division.id, 0) > @split_bytes and length(scenes) >= 2 do
        [%{page | split: true} | Enum.map(scenes, &scene_page_for(page, &1))]
      else
        [page]
      end
    end)
  end

  defp text_bytes(item), do: byte_size(item.element.content || "")

  defp scene_page_for(page, scene) do
    %{
      slug: "#{page.slug}-s#{scene.position + 1}",
      title: "#{page.title}, #{scene_title(scene)}",
      division: page.division,
      scene: scene,
      split: false
    }
  end

  @doc "A scene's heading, or its number when it has none."
  def scene_title(scene), do: scene.title || "Scene #{scene.position + 1}"

  @doc "The page a scene has to itself, or nil when it shares its division's page."
  def scene_page(%__MODULE__{pages: pages}, scene),
    do: Enum.find(pages, &(&1.scene && &1.scene.id == scene.id))
```

Replace `defp page_of/2` with:

```elixir
  defp page_of(pages, items) do
    slug_of =
      Map.new(pages, fn
        %{scene: nil} = page -> {page.division.id, page.slug}
        page -> {page.scene.id, page.slug}
      end)

    for item <- items,
        slug when not is_nil(slug) <-
          [(item.scene && slug_of[item.scene.id]) || slug_of[item.division.id]],
        into: %{},
        do: {item.element.id, slug}
  end
```

In `anchors/2`, replace `Enum.flat_map(pages, fn page ->` with `pages |> Enum.reject(& &1.scene) |> Enum.flat_map(fn page ->` (a scene page's division is already listed through its own page).

- [ ] **Step 4: Render scene pages and link them**

In `lib/playcode/export/static_site/components.ex`, replace `play_contents/1` with:

```elixir
  attr :edition, :map, required: true
  attr :current, :string, default: nil
  attr :all_scenes, :boolean, default: false

  def play_contents(assigns) do
    ~H"""
    <ul>
      <li><a href="index.html" aria-current={@current == "index" && "page"}>Title page</a></li>
      <li :for={page <- Enum.reject(@edition.pages, & &1.scene)}>
        <a href={page.slug <> ".html"} aria-current={@current == page.slug && "page"}>{page.title}</a>
        <ul :if={(@all_scenes or open?(@edition, page, @current)) and page.division.children != []}>
          <li :for={scene <- page.division.children}>
            <%= if scene_page = Edition.scene_page(@edition, scene) do %>
              <a href={scene_page.slug <> ".html"} aria-current={@current == scene_page.slug && "page"}>
                {Edition.scene_title(scene)}
              </a>
            <% else %>
              <a href={"#{page.slug}.html##{@edition.anchors[scene.id]}"}>{Edition.scene_title(scene)}</a>
            <% end %>
          </li>
        </ul>
      </li>
      <li><a href="text.html" aria-current={@current == "text" && "page"}>Full text</a></li>
      <li>
        <a href="statistics.html" aria-current={@current == "statistics" && "page"}>Statistics</a>
      </li>
    </ul>
    """
  end

  # A division's scenes show in the rail on its page and on its scene pages.
  defp open?(edition, page, current) do
    current == page.slug or
      Enum.any?(edition.pages, &(&1.scene && &1.division.id == page.division.id and &1.slug == current))
  end
```

Add after `division_text/1`:

```elixir
  attr :edition, :map, required: true
  attr :page, :map, required: true

  @doc """
  What one division page shows: the division whole; or, for a division split by scene,
  its own text and a list of its scene pages; or one scene of it.
  """
  def page_text(%{page: %{scene: nil, split: false}} = assigns) do
    ~H"""
    <.division_text edition={@edition} division={@page.division} />
    """
  end

  def page_text(%{page: %{scene: nil, split: true}} = assigns) do
    assigns =
      assign(
        assigns,
        :scene_pages,
        Enum.filter(assigns.edition.pages, &(&1.scene && &1.division.id == assigns.page.division.id))
      )

    ~H"""
    <section class="division" id={@edition.anchors[@page.division.id]}>
      <h2 :if={@page.division.title} class="act-head">{@page.division.title}</h2>
      <.el :for={el <- @page.division.loaded_elements} el={el} edition={@edition} />
      <nav aria-label="Scenes">
        <ul>
          <li :for={scene_page <- @scene_pages}>
            <a href={scene_page.slug <> ".html"}>{Edition.scene_title(scene_page.scene)}</a>
          </li>
        </ul>
      </nav>
    </section>
    """
  end

  def page_text(assigns) do
    ~H"""
    <section class="division">
      <h2 :if={@page.division.title} class="act-head">{@page.division.title}</h2>
      <section id={@edition.anchors[@page.scene.id]}>
        <h3 :if={@page.scene.title} class="scene-head">{@page.scene.title}</h3>
        <.el :for={el <- @page.scene.loaded_elements} el={el} edition={@edition} />
      </section>
    </section>
    """
  end
```

In `pages/division.html.heex`, replace `<Components.division_text edition={@edition} division={@page.division} />` with `<Components.page_text edition={@edition} page={@page} />`.

In `pages/text.html.heex`, replace `:for={page <- @edition.pages}` with `:for={page <- Enum.reject(@edition.pages, & &1.scene)}`.

- [ ] **Step 5: Run the tests**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode/export/static_site_test.exs`
Expected: PASS, including the older tests (no fixture there has 120,000 bytes in one division).

- [ ] **Step 6: Check the dev corpus, run everything, commit**

Run `mix playcode.export.site --all -o <scratchpad>/site` and record the printed largest act page (it should now be under 80 KB) and which plays got scene pages (`ls <scratchpad>/site/plays/*/ | grep -- '-s[0-9]*.html' | head`). Expected: EMOTHE0084, EMOTHE0254 and EMOTHE0648 only.

Run: `mix format && mix compile --warnings-as-errors && mix test`

```bash
git add lib/playcode/export/static_site/edition.ex lib/playcode/export/static_site/components.ex lib/playcode/export/static_site/pages/division.html.heex lib/playcode/export/static_site/pages/text.html.heex test/playcode/export/static_site_play_test.exs
git commit -m "feat: a page per scene for a division over 120,000 bytes of text

Three French prose translations keep most of the play in one division;
their act pages were 85-87 KB gzipped with 200 KB of text. Such a division
keeps its own page, now listing its scenes, and each scene gets a page.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `plays.form`, set by hand, kept across imports

**Files:**
- Create: `priv/repo/migrations/20261002120000_add_form_to_plays.exs`
- Modify: `lib/playcode/catalogue/play.ex`, `lib/playcode/import/tei_parser.ex`, `lib/playcode_web/play_labels.ex`, `lib/playcode_web/live/admin/play_form_live.ex`, `priv/gettext/**`
- Test: `test/playcode_web/live/admin/play_form_live_test.exs`, `test/playcode/import/tei_preview_test.exs`, `test/playcode/import/tei_reimport_test.exs`

**Interfaces:**
- Produces: `Play.forms() :: ~w(verse prose mixed)`, `Play.form(%Play{}) :: "verse" | "prose" | "mixed"`; `PlaycodeWeb.PlayLabels.form_label/1`, `form_options/1`.

- [ ] **Step 1: Write the tests**

In `test/playcode_web/live/admin/play_form_live_test.exs`, add `alias Playcode.Catalogue.Play` under `alias Playcode.Catalogue`, then:

```elixir
  test "a play's form can be set by hand, and later edits to its text keep it",
       %{conn: conn} do
    %{play: play, line_group: line_group, scene: scene} = play_with_structure_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{"form" => "prose"})
    assert play.id |> Catalogue.get_play!() |> Play.form() == "prose"

    # A content edit recomputes is_verse from the verse lines; the curator's choice stands.
    {:ok, _} =
      Playcode.PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        type: "verse_line",
        content: "otro verso",
        line_number: 99,
        position: 99
      })

    assert play.id |> Catalogue.get_play!() |> Play.form() == "prose"
  end

  test "left automatic, the form follows the text", %{conn: conn} do
    %{play: play} = play_with_structure_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{"form" => ""})

    saved = Catalogue.get_play!(play.id)
    assert saved.form == nil
    assert Play.form(saved) == if(saved.is_verse, do: "verse", else: "prose")
  end
```

Check `create_element/1`'s required attributes against `lib/playcode/play_content/element.ex` and the existing statistics test that creates an aside verse; adjust the map if it needs more, and say so in the report.

In `test/playcode/import/tei_preview_test.exs`, in "an existing play reports what is replaced and what is kept", replace `{:ok, _} = Catalogue.update_play(play, %{language: "en"})` with `{:ok, _} = Catalogue.update_play(play, %{language: "en", form: "mixed"})` and add `assert :form in preview.preserves_fields` after `assert :language in preview.preserves_fields`.

In `test/playcode/import/tei_reimport_test.exs`, in "curated columns survive a re-import", add `form: "mixed",` to the `curated` map.

Search the test suite for `is_verse` in form submissions (`grep -rn '"is_verse"' test/playcode_web`); a test that fills the old checkbox must move to the select, with a comment saying why.

- [ ] **Step 2: Run them**

Run: `mix test test/playcode_web/live/admin/play_form_live_test.exs test/playcode/import/tei_preview_test.exs test/playcode/import/tei_reimport_test.exs`
Expected: FAIL — `Play.form/1` is undefined (compile error in the test module); `form/3` finds no `play[form]` field.

- [ ] **Step 3: Migration, schema, labels**

`priv/repo/migrations/20261002120000_add_form_to_plays.exs`:

```elixir
defmodule Playcode.Repo.Migrations.AddFormToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      # nil means automatic: Playcode.Catalogue.Play.form/1 derives it from is_verse.
      add :form, :string
    end
  end
end
```

In `lib/playcode/catalogue/play.ex`: add `field :form, :string` after `field :is_verse, :boolean, default: true`; add `:form` to the `cast` list after `:is_verse`; add `|> validate_inclusion(:form, @forms)` after the `:relationship_type` inclusion; and, after `def historical_times`:

```elixir
  @forms ~w(verse prose mixed)

  def forms, do: @forms

  @doc """
  The play's form as every page names it: the curator's choice when set, else "verse"
  when the text has any verse and "prose" otherwise. `is_verse` is recomputed from the
  verse lines on every import and content edit, so the automatic value follows the text;
  only a curator says "mixed".
  """
  def form(%__MODULE__{form: form}) when is_binary(form), do: form
  def form(%__MODULE__{is_verse: true}), do: "verse"
  def form(%__MODULE__{}), do: "prose"
```

In `lib/playcode/import/tei_parser.ex`, add `:form` as the last entry of `@platform_owned`.

In `lib/playcode_web/play_labels.ex`, after `historical_time_options/0`:

```elixir
  @doc "The name of a play's form, as `Play.form/1` gives it."
  def form_label("verse"), do: gettext("Verse")
  def form_label("prose"), do: gettext("Prose")
  def form_label("mixed"), do: gettext("Verse and prose")

  @doc "The form select's options: automatic first, saying what it currently gives."
  def form_options(%Play{} = play) do
    automatic = Play.form(%{play | form: nil})

    [
      {gettext("Automatic (%{form})", form: form_label(automatic)), nil}
      | Enum.map(Play.forms(), &{form_label(&1), &1})
    ]
  end
```

(`Play` is already aliased in `play_labels.ex` — `historical_time_options/0` uses it; add the alias if not.)

- [ ] **Step 4: The select in the admin form**

In `lib/playcode_web/live/admin/play_form_live.ex`, delete the "Verse play" checkbox block:

```heex
          <div class="rounded-box bg-base-200 px-3 py-2">
            <label class="flex items-center gap-2 text-sm text-base-content/85">
              <.input field={@form[:is_verse]} type="checkbox" /> {gettext("Verse play")}
            </label>
          </div>
```

and add, in the Research Metadata fieldset, before the Historical Time `<div>`:

```heex
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Form")}</span>
            </label>
            <.input field={@form[:form]} type="select" options={PlayLabels.form_options(@play)} />
            <p class="mt-1 text-xs text-base-content/60">
              {gettext("Automatic follows the text: verse when it has any verse lines.")}
            </p>
          </div>
```

If the new-play page has no `@play` assign, pass `%Play{}` (check `mount/3` for `:new`; line 35 and 66 assign `:play` in both actions today).

- [ ] **Step 5: Translate, migrate, run the tests**

Run: `mix ecto.migrate && MIX_ENV=test mix ecto.migrate`, then `mix gettext.extract --merge`. In `priv/gettext/es/LC_MESSAGES/default.po` give the new entries their Spanish and check every entry the merge marked `#, fuzzy`:

| msgid | Spanish msgstr |
|---|---|
| Verse | Verso |
| Verse and prose | Verso y prosa |
| Automatic (%{form}) | Automático (%{form}) |
| Form | Forma |
| Automatic follows the text: verse when it has any verse lines. | Automático sigue el texto: verso si tiene algún verso. |

Keep any existing translation of "Verse", "Prose" or "Form" that is already right.

Run: `mix test test/playcode_web/live/admin/play_form_live_test.exs test/playcode/import/tei_preview_test.exs test/playcode/import/tei_reimport_test.exs`
Expected: PASS.

- [ ] **Step 6: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`

```bash
git add priv/repo/migrations/20261002120000_add_form_to_plays.exs lib/playcode/catalogue/play.ex lib/playcode/import/tei_parser.ex lib/playcode_web/play_labels.ex lib/playcode_web/live/admin/play_form_live.ex priv/gettext test/playcode_web/live/admin/play_form_live_test.exs test/playcode/import/tei_preview_test.exs test/playcode/import/tei_reimport_test.exs
git commit -m "feat: a play's form can be set by hand: verse, prose or both

plays.form overrides the automatic label, which says verse whenever the
text has a verse line. The old Verse play checkbox wrote is_verse, which
the next content edit recomputed; the select's value stands, and a TEI
re-import keeps it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Every page names the form through `Play.form/1`

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex`, `lib/playcode/export/static_site.ex`, `lib/playcode/export/static_site/pages/title.html.heex`, `pages/statistics.html.heex`, `lib/playcode_web/live/play_show_live.ex`
- Test: `test/playcode/export/static_site_catalogue_test.exs`, `test/playcode/export/static_site_test.exs`, `test/playcode/export/static_site_play_test.exs`, `test/playcode_web/live/play_show_live_test.exs`

**Interfaces:**
- Consumes: `Play.form/1`, `PlayLabels.form_label/1` (Task 6).
- Produces: `Components.form_summary(play, stats) :: String.t()`.

- [ ] **Step 1: Write the tests**

In `test/playcode/export/static_site_catalogue_test.exs`:

```elixir
  test "the Form facet follows a curator's choice over the automatic one" do
    verse = play_fixture(%{"is_complete" => true})
    prose = play_fixture(%{"is_complete" => true, "form" => "prose"})
    mixed = play_fixture(%{"is_complete" => true, "form" => "mixed"})

    index = html!(generate!([verse, prose, mixed]), "index.html")
    labels = texts(index, "[data-facets] label")

    assert "Verse 1" in labels
    assert "Prose 1" in labels
    assert "Verse and prose 1" in labels

    assert index |> LazyHTML.query("[data-play]") |> LazyHTML.attribute("data-form") |> Enum.sort() ==
             ["mixed", "prose", "verse"]
  end
```

In `test/playcode/export/static_site_test.exs`:

```elixir
  test "the title page names the curator's form" do
    prose = complete_play(%{"form" => "prose"})
    mixed = complete_play(%{"form" => "mixed"})
    bare_verse = complete_play(%{"form" => "verse"})
    dir = generate!([prose, mixed, bare_verse])
    form = fn play -> title_page(dir, play) |> LazyHTML.query("dd") |> Enum.map(&squish(LazyHTML.text(&1))) end

    assert "Prose" in form.(prose)
    assert Enum.any?(form.(mixed), &String.starts_with?(&1, "Verse and prose"))
    # A fixture play has no verse lines: no "· 0 verses".
    assert "Verse" in form.(bare_verse)
  end
```

In `test/playcode/export/static_site_play_test.exs`, inside `describe "the statistics page"`:

```elixir
    test "a verse play its curator calls prose measures its characters in words" do
      play = import_tei!(tei(body: @two_acts))
      {:ok, play} = Playcode.Catalogue.update_play(play, %{form: "prose"})
      dir = generate!([play], all: true)

      assert LazyHTML.text(page(dir, play, "statistics.html")) =~ "most words"
    end
```

In `test/playcode_web/live/play_show_live_test.exs`, add (using the module's existing helpers for a published play; read the file's other tests for how a play is made visible at `/plays/:code`):

```elixir
  test "the play's form is the curator's when one is set", %{conn: conn} do
    play =
      import_tei!(
        tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">un verso</l></sp></div1>))
      )

    {:ok, _} = Playcode.Catalogue.update_play(play, %{form: "mixed"})
    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert html =~ t("Verse and prose")
  end
```

- [ ] **Step 2: Run them**

Run: `mix test test/playcode/export test/playcode_web/live/play_show_live_test.exs`
Expected: FAIL — the facets still count `is_verse` (no "Verse and prose"), the title page says "Verse · 1 verses" for the prose play, the statistics lede says "most lines", the live page shows "1 versos".

- [ ] **Step 3: Read the form through `Play.form/1`**

In `lib/playcode/export/static_site/components.ex`, replace `form_summary/1` with:

```elixir
  @doc "What the title page says about the play's form."
  def form_summary(play, stats) do
    verses = stats["verses"] || 0

    case {Play.form(play), verses} do
      {"prose", _} -> "Prose"
      {"verse", n} when n > 0 -> "Verse · #{number(n)} verses"
      {"verse", _} -> "Verse"
      {"mixed", n} when n > 0 -> "Verse and prose · #{number(n)} verses"
      {"mixed", _} -> "Verse and prose"
    end
  end
```

In `catalogue_entry/1`, replace `data-form={if @play.is_verse, do: "verse", else: "prose"}` with `data-form={Play.form(@play)}`, and replace `entry_meta/1` with:

```elixir
  defp entry_meta(play) do
    form =
      case Play.form(play) do
        "prose" -> "Prose"
        "mixed" -> "Verse and prose"
        "verse" when is_integer(play.verse_count) and play.verse_count > 0 -> "#{number(play.verse_count)} vv."
        "verse" -> "Verse"
      end

    [composition_years(play), form] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end
```

In `lib/playcode/export/static_site.ex`, in `facets/1`, replace the Form entry with:

```elixir
      {"form", "Form",
       options(plays, &Play.form/1, %{
         "verse" => "Verse",
         "prose" => "Prose",
         "mixed" => "Verse and prose"
       })},
```

In `pages/title.html.heex`, replace `{Components.form_summary(@edition.stats)}` with `{Components.form_summary(@edition.play, @edition.stats)}`.

In `pages/statistics.html.heex`, replace the `unit=` and `total=` attributes of `<Components.character_table …>` with:

```heex
    unit={if words_unit?(@edition), do: "words", else: "lines"}
    total={if words_unit?(@edition), do: @edition.stats["words"] || 0, else: @edition.stats["verses"]}
```

and add to `lib/playcode/export/static_site/pages.ex`:

```elixir
  # Characters are measured in lines in a verse play, in words in anything else.
  defp words_unit?(edition),
    do: Play.form(edition.play) != "verse" or (edition.stats["verses"] || 0) == 0
```

In `lib/playcode_web/live/play_show_live.ex`, replace the `{if @play.verse_count do … end}` expression after `Play.language_name(@play.language)` with `{" · " <> form_line(@play)}`, add `alias Playcode.Catalogue.Play` if absent, and add:

```elixir
  defp form_line(play) do
    case {Play.form(play), play.verse_count} do
      {"prose", _} -> PlayLabels.form_label("prose")
      {form, n} when is_integer(n) and n > 0 -> "#{PlayLabels.form_label(form)} · #{n} #{gettext("verses")}"
      {form, _} -> PlayLabels.form_label(form)
    end
  end
```

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode/export test/playcode_web/live/play_show_live_test.exs`
Expected: PASS. An older test may assert "Verse · N verses" or the live page's "N versos" wording; if one contradicts the new line on purpose, update it with a comment saying why.

- [ ] **Step 5: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test`

```bash
git add lib/playcode/export lib/playcode_web/live/play_show_live.ex test/playcode/export test/playcode_web/live/play_show_live_test.exs
git commit -m "feat: catalogue, title page, statistics and live page name the curator's form

Every place that said Verse or Prose now reads Play.form/1: a prose play
with two songs can be called prose, and a mixed play verse and prose.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Documentation

**Files:**
- Modify: `CLAUDE.md`, `docs/static-site-improvements.md`

- [ ] **Step 1: CLAUDE.md**

1. In **Static Site Export › Architecture**, replace the `StaticSite.Search` bullet with:

```markdown
- `StaticSite.Search` — the normaliser (must agree with `EMOTHE.normalise` in `site.js`: `test/fixtures/search_normalisation.json` runs against both) and the index: `search/plays.js`, `search/index/<shard>.js` (per play `[play, n, deltas…]`, `delta = (line − previous) × 2 + stage flag`) and `search/lines/<CODE>/<k>.js` (100 lines each), all calling `EMOTHE.search.load`. `write_index/3` carries every play's postings over from the shards on disk, so adding or removing a play reloads no other; an index older than chunked lines is rebuilt in full
```

and add after the `StaticSite.Edition` bullet:

```markdown
- A division with more than 120,000 bytes of text and two or more scenes also gets a page per scene (`act-1-s3.html`); `generate/1` builds plays concurrently (`Task.async_stream`, at most the pool size minus two)
```

2. In **Output structure**, change `search/                    plays.js, index/<shard>.js, lines/<CODE>.js` to `search/                    plays.js, index/<shard>.js, lines/<CODE>/<k>.js` and `act-1.html …       one per act; prologue.html etc. for other divisions` to `act-1.html …       one per act (act-1-s3.html … per scene for a very long act); prologue.html etc.`.

3. In **Database Schema**, add to the `plays` line: `; `form` is nil (automatic, from `is_verse`) or a curator's `verse`/`prose`/`mixed`, read only through `Play.form/1``.

4. In **Archiving and provenance**, add `form` to the list of columns a re-import does not write.

5. In the paragraph on the size budget, add: `On the full dev corpus every act page is under 80 KB gzipped and a first search costs at most ~165 KB gzipped (follow-ups spec, "What was measured").` — only if Task 5 Step 6 and Task 2 Step 5 confirmed it; otherwise state the numbers they measured.

- [ ] **Step 2: `docs/static-site-improvements.md`**

In item 5, replace the "Being fixed" paragraph with one saying it is done, with the follow-ups spec and the commits of Tasks 1, 2 and 5, and the measured numbers from Task 2 Step 5 and Task 5 Step 6.

- [ ] **Step 3: Verify and commit**

Run: `mix test test/rename_guard_test.exs && mix test`

```bash
git add CLAUDE.md docs/static-site-improvements.md
git commit -m "docs: chunked search, incremental index, scene pages and plays.form

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
