# Static Site Downloads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the published site, a play with a text offers its TEI file, an EPUB written by Generate, and a print button that gives paper or a PDF through the browser.

**Architecture:** `StaticSite.write_play/4` writes `plays/CODE/CODE.epub` beside the play's pages, from the existing `Export.Epub`, made to give the same bytes for the same play. The title page gets a Downloads section. Printing is the browser's own, over the site's print styles, started by a button on the full-text page; no PDF file is made, stored or deployed.

**Tech Stack:** Elixir, BUPE (EPUB), Erlang `:zip`, HEEx templates, plain browser JavaScript, ExUnit.

**Spec:** `docs/superpowers/specs/2026-11-17-plays-without-text-and-record-search-design.md`, section 7.7, the measurements in section 5 (*Downloads and their cost*) and section 6, *PDF on the published site* (why no PDF files). Read them before Task 1.

**Needs:** plan `2026-11-17-plays-without-text.md` merged (`Play.has_text?/1`; a play without a text has `index.html` and its TEI file alone). Independent of the search plans; if `2026-11-17-catalogue-search-filters.md` is merged, `test/support/browser.ex` exists and Task 3 uses it.

## Global Constraints

- Work on branch `feature/static-site-downloads` in a git worktree of its own. Check the branch before every commit.
- Every task is red, green, refactor, then commit. Prove a test bites with `bin/bites` when it passes at once.
- The site stays Endings: no third-party request, everything works from `file://`.
- Budgets (`test/playcode/export/static_site_test.exs`, line 584): `style.css` ≤ 25,000 bytes (24,842 on 2026-11-17, more room once the catalogue's rules have left), `site.js` ≤ 15,000 (13,669).
- A change to the EPUB's code must rebuild every play: its modules are in `StaticSite.Fingerprint`, and `test/playcode/export/static_site/fingerprint_test.exs` decides which.
- A play without a text gets no EPUB and no print link.
- The preview's downloads (`/export/:id/*`, `PdfCache`) are not touched.
- Interface words in both languages through the site's `t/1`; Spanish: "Descargas", "Imprimir o guardar como PDF".
- Plain `mix test PATH`; `mix format`; no `Co-Authored-By` trailer.

## Review Focus

1. **A full rebuild after a code change** (every play built again): each unchanged play's `CODE.epub` is byte for byte what it was, so Deploy pushes none of them. Test in Task 1.
2. **A play that loses its text, or leaves the site**: its `CODE.epub` goes with its pages. Test in Task 2.
3. **A title or author with italics or an ampersand** (`La <<Celestina>>`, `Beaumont & Fletcher`): the EPUB still builds and every chapter parses. Test in Task 1.
4. **A reader with scripts off**: no dead print button; the Downloads section still offers the TEI file and the EPUB, and the print link opens the full text, which the browser's own print command prints. Test in Task 3.
5. **A reader who opens `text.html#print` from `file://`**: the print dialogue opens once, after the page has loaded, and not again on reload of an address without the hash. Checked by hand in Task 3, Step 6.

---

### Task 1: The same play gives the same EPUB

**Files:**
- Modify: `lib/playcode/export/epub.ex` (`generate/1` at line 13; the `BUPE.Config` near 70; the `BUPE.build` call near 89)
- Test: `test/playcode_web/controllers/export_controller_test.exs` (where the EPUB's tests live), or a new `test/playcode/export/epub_test.exs` if those tests need no route

**Interfaces:**
- Produces: `Export.Epub.generate(play) :: {:ok, binary} | {:error, term}` unchanged in shape; the book's `dcterms:modified` is `play.updated_at` (ISO 8601, `Z`), and every entry of the archive carries that time. `mimetype` stays the first entry, stored uncompressed.

- [ ] **Step 1: Write the failing tests.**

```elixir
defp entries(epub) do
  {:ok, table} = :zip.table(epub)
  for {:zip_file, name, info, _comment, _offset, _size} <- table, do: {to_string(name), elem(info, 5)}   # mtime
end

test "an EPUB's times are its play's, not the clock's" do
  play = text_play()
  {:ok, epub} = Export.Epub.generate(Catalogue.get_play_with_all!(play.id))
  stamp = play.updated_at |> DateTime.to_naive() |> NaiveDateTime.to_erl()
  assert entries(epub) |> Enum.map(&elem(&1, 1)) |> Enum.uniq() == [stamp]
  {:ok, files} = :zip.unzip(epub, [:memory])
  opf = Enum.find_value(files, fn {name, body} -> if String.ends_with?(to_string(name), ".opf"), do: body end)
  assert opf =~ ~s(<meta property="dcterms:modified">#{DateTime.to_iso8601(play.updated_at)}</meta>)
end

test "the archive opens with its mimetype, stored as it is" do
  {:ok, epub} = Export.Epub.generate(Catalogue.get_play_with_all!(text_play().id))
  assert [{"mimetype", _} | _] = entries(epub)
  assert binary_part(epub, 30, 8) == "mimetype"                       # the first local header's name
  assert :binary.match(epub, "application/epub+zip") != :nomatch      # readable: not compressed
end

test "a title with italics and an author with an ampersand build a book whose chapters parse" do   # Review Focus 3
  play = text_play(%{"title" => "La <<Celestina>>", "author_name" => "Beaumont & Fletcher"})
  {:ok, epub} = Export.Epub.generate(Catalogue.get_play_with_all!(play.id))
  {:ok, files} = :zip.unzip(epub, [:memory])
  for {name, body} <- files, String.ends_with?(to_string(name), ".xhtml"),
      do: assert {:ok, _} = Saxy.SimpleForm.parse_string(body)
end
```

`text_play/1` is a private helper of each test file here: `play_with_structure_fixture().play` (`test/support/fixtures.ex`: an act, a speech, verse lines) updated with the given attributes through `Catalogue.update_play/2` and read back. Adjust `entries/1` to the tuple `:zip.table/1` really returns on OTP 28 (`#zip_file{}` holds a `#file_info{}`; its `mtime` is the sixth field). If the third test already passes, prove it bites or drop it and say what covers it.

- [ ] **Step 2: Run** the file — expected: FAIL on the first test (the times are the moment of the build).

- [ ] **Step 3: Implement.** Give `BUPE.Config` `modified: DateTime.to_iso8601(play.updated_at)`. After `BUPE.build/3` returns the binary, write the archive again with fixed times: `:zip.unzip(binary, [:memory])`, then `:zip.create/3` in memory with each entry as `{name, body, file_info}` whose `mtime` (and `atime`, `ctime`) is the play's `updated_at`, `mimetype` first, and the same `uncompress` list BUPE passes (`deps/bupe/lib/bupe/builder.ex`, near line 130) so `mimetype` stays stored. A private `stable/2` holds it, with a comment saying why (spec 7.7).

- [ ] **Step 4: Run** the file and `mix test test/playcode_web/controllers/export_controller_test.exs` — expected: PASS, the existing EPUB tests among them.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: Commit** — `fix: the same play gives the same EPUB, byte for byte`

---

### Task 2: Generate writes each play's EPUB, and the title page offers the downloads

**Files:**
- Modify: `lib/playcode/export/static_site.ex` (`write_play/4` at 549)
- Modify: `lib/playcode/export/static_site/pages/title.html.heex` (the last `<p>`, the TEI link)
- Modify: `lib/playcode/export/static_site/components.ex` (a `downloads/1` component beside `licence/1`)
- Modify: `lib/playcode/export/static_site/fingerprint.ex` (`@modules`)
- Test: `test/playcode/export/static_site_play_test.exs`, `test/playcode/export/static_site_changes_test.exs`, `test/playcode/export/static_site/fingerprint_test.exs`

**Interfaces:**
- Consumes: `Export.Epub.generate/1` (Task 1); `Play.has_text?/1`.
- Produces: `plays/CODE/CODE.epub` for every published play with a text; on its title page `<section class="downloads">` with an `h2` "Descargas" / "Downloads" and three links: `CODE.xml` (`download`), `CODE.epub` (`download`), `text.html#print`. A play without a text: the section with the TEI link alone.

- [ ] **Step 1: Write the failing tests.**

```elixir
# static_site_play_test.exs
test "a play's EPUB is published beside its pages, the book staff download" do
  play = text_play(%{"is_complete" => true})
  dir = generate!([play])
  {:ok, expected} = Playcode.Export.Epub.generate(Catalogue.get_play_with_all!(play.id))
  assert File.read!(Path.join(dir, "plays/#{play.code}/#{play.code}.epub")) == expected
end

test "the title page offers the TEI file, the EPUB and print, under Downloads" do
  play = text_play(%{"is_complete" => true})
  page = html!(generate!([play]), "plays/#{play.code}/index.html", "es")
  section = LazyHTML.query(page, "section.downloads")
  assert texts(section, "h2") == ["Descargas"]
  assert section |> LazyHTML.query("a") |> LazyHTML.attribute("href") == ["#{play.code}.xml", "#{play.code}.epub", "text.html#print"]
  assert section |> LazyHTML.query("a[download]") |> Enum.count() == 2
  assert texts(section, "a") |> List.last() == "Imprimir o guardar como PDF"
end

test "a play without a text offers its TEI file alone, and has no EPUB" do
  play = play_without_text_fixture(%{"is_complete" => true})
  dir = generate!([play])
  refute File.exists?(Path.join(dir, "plays/#{play.code}/#{play.code}.epub"))
  assert html!(dir, "plays/#{play.code}/index.html") |> LazyHTML.query("section.downloads a") |> LazyHTML.attribute("href") == ["#{play.code}.xml"]
end

test "building an unchanged play again gives the same EPUB" do                    # Review Focus 1
  play = text_play(%{"is_complete" => true})
  dir = generate!([play])
  path = Path.join(dir, "plays/#{play.code}/#{play.code}.epub")
  before = File.read!(path)
  :ok = StaticSite.generate_single_play(play.id, output_dir: dir)
  assert File.read!(path) == before
end

# static_site_changes_test.exs — Review Focus 2
test "a play taken off the site takes its EPUB with it" do
  play = text_play(%{"is_complete" => true})
  dir = generate!([play, play_fixture(%{"is_complete" => true})])
  {:ok, _} = StaticSite.apply_changes([{:remove, play.code}], output_dir: dir)
  refute File.exists?(Path.join(dir, "plays/#{play.code}/#{play.code}.epub"))
end
```

"Building again gives the same EPUB" can pass by luck inside one second; it is Task 1's first test that holds the rule, so say in a comment that this one checks the wiring.

- [ ] **Step 2: Run** the two files — expected: FAIL, no `.epub` file and no `section.downloads`.

- [ ] **Step 3: Implement.** In `write_play/4`, for a play with a text, after the TEI file: `{:ok, epub} = Epub.generate(play)` and write it; a build that cannot make a play's EPUB fails loudly, as one that cannot render a page does. `Components.downloads/1` takes the play; `title.html.heex` calls it in place of the TEI paragraph.

- [ ] **Step 4: Run** `mix test test/playcode/export` — expected: `fingerprint_test.exs` FAILS, naming the modules the export now calls that are not fingerprinted (`Playcode.Export.Epub`, `Playcode.Export.Download`, `Playcode.Export.Html`, and whatever they reach). Add exactly the modules it names to `Fingerprint`'s `@modules`, with a line in the `@moduledoc` saying the EPUB is part of a play's pages. Run again — expected: PASS.

- [ ] **Step 5: Measure.** `mix playcode.export.site --all -o /tmp/site-downloads` twice (or the task's real flags: `mix help playcode.export.site`), timing each, then `du -sh /tmp/site-downloads` and `find /tmp/site-downloads -name '*.epub' | xargs du -ch | tail -1`. The design measured 65 s and 33 MB for 407 EPUBs on a laptop; a build more than two minutes slower than before, or EPUBs over 60 MB, is something to tell the owner before going on. Run the second build's EPUBs against the first's with `diff -rq` on two copies: no `.epub` may differ.

- [ ] **Step 6: Refactor while green; gettext** (Spanish: `Descargas`, `Imprimir o guardar como PDF`); **commit** — `feat: the site publishes each play's EPUB and lists its downloads`

---

### Task 3: The print button

**Files:**
- Modify: `lib/playcode/export/static_site/pages/text.html.heex`
- Modify: `priv/static_site/site.js` (a new `initPrint`, called beside `initTools()` near line 303; `E.align` at line 52 is what it calls)
- Modify: `priv/static_site/style.css` (the `@media print` rule at line 308 gains `[data-print]`)
- Test: `test/playcode/export/static_site_play_test.exs`; `test/playcode/export/static_site_browser_test.exs` when `test/support/browser.ex` exists

**Interfaces:**
- Produces: on `text.html`, `<button type="button" class="copy" data-print hidden>` with the words "Imprimir o guardar como PDF" / "Print or save as PDF", above the text. `site.js`: shows it, prints on click, prints once on load when `location.hash === '#print'`; on `beforeprint` removes `data-aligned` from every shared line under `document`, on `afterprint` calls `E.align(document)`.

- [ ] **Step 1: Write the failing tests.**

```elixir
# static_site_play_test.exs
test "the full text has a print button, hidden until the script shows it, and never printed" do   # Review Focus 4
  play = text_play(%{"is_complete" => true})
  dir = generate!([play])
  button = html!(dir, "plays/#{play.code}/text.html", "es") |> LazyHTML.query("button[data-print]")
  assert LazyHTML.attribute(button, "hidden") == [""]
  assert texts(button, "button") == ["Imprimir o guardar como PDF"]
  assert read!(dir, "assets/style.css") =~ ~r/@media print \{[^@]*\[data-print\]/s
end

# static_site_browser_test.exs, only when Playcode.Browser exists
test "the script shows the print button", %{dir: dir, verse: verse} do
  page = Browser.dom!(dir, "plays/#{verse.code}/text.html")
  assert page |> LazyHTML.query("button[data-print]") |> LazyHTML.attribute("hidden") == []
end
```

- [ ] **Step 2: Run** — expected: FAIL, no `button[data-print]`.
- [ ] **Step 3: Implement.** The button in `text.html.heex`; `initPrint` in `site.js` (about fifteen lines); `[data-print]` added to the print rule's selector list.
- [ ] **Step 4: Run** `mix test test/playcode/export`, `node --test test/js/*.test.mjs`, and the browser test when it exists — expected: PASS; the budgets hold (`wc -c priv/static_site/site.js priv/static_site/style.css`).
- [ ] **Step 5: Refactor while green.**
- [ ] **Step 6: By hand, from disk (Review Focus 5).** Open `/tmp/site-downloads/plays/<a verse play with shared lines>/index.html` as `file://`: follow "Imprimir o guardar como PDF" (the dialogue opens once); in the preview, a shared line's later parts sit at their fixed step and none wraps; the rail, the bar and the button are not on the paper; cancel, and the screen's alignment is back; reload without the hash: no dialogue. Then with JavaScript off: no button, and the browser's own print gives the same pages. Note in the commit body what you did and saw.
- [ ] **Step 7: Commit** — `feat: the full text prints, or saves as PDF, from a button`

---

### Task 4: The documents, the whole suite

**Files:**
- Modify: `docs/static-site.md` (the downloads; the EPUB in the fingerprint; the measured time and size with their date; why no PDF files, pointing at the spec's section 6), `docs/architecture.md` (file map), `docs/stakeholder/ida-y-vuelta.html` (the static site's column: EPUB yes, PDF by the browser's print)
- Modify: `docs/backlog.md` (in *A shared line's lead carries no note numbers*, the sentence on a browser's print of the site is done; the HTML download's half stays) and `docs/history.md`

- [ ] **Step 1:** Write the documents.
- [ ] **Step 2: Run** `mix precommit` and `node --test test/js/*.test.mjs` — expected: 0 failures. Paste both summaries into the commit body.
- [ ] **Step 3: Commit** — `docs: the site's downloads`
- [ ] **Step 4:** Tell the owner the branch is ready to merge, that the first Generate after it rebuilds every play (the fingerprint moved) and the first Deploy pushes about 33 MB of EPUBs. No pull request; merge and push only when told.
