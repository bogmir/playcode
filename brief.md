# Playcode daily brief 2026-11-25 (main @ d92652d)
Current focus: none.

## 19 of 73 questions open ([preguntas](docs/stakeholder/preguntas.html))
**5 easiest**
- [q72](docs/stakeholder/preguntas.html#q72) RoleCall link for translations: yes/no.
- [q70](docs/stakeholder/preguntas.html#q70) Character genders: pick a word list (Woman/man/X proposed).
- [q71](docs/stakeholder/preguntas.html#q71) Where readers see gender: tick boxes.
- [q28](docs/stakeholder/preguntas.html#q28) Show original-cast actors to readers: yes/no.
- [q7](docs/stakeholder/preguntas.html#q7) The Rover's 40 hidden stage directions: show or not.

**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays wait on a yes (backlog C1).
- [q69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays: blocks the Numbering section, then a Generate.
- [q53](docs/stakeholder/preguntas.html#q53) Which "version" plays are originals: gates the relations design (q53-57) and family fixes.
- [q14](docs/stakeholder/preguntas.html#q14) Pyrame et Thisbé editions and three plays with no text: corpus completeness.
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: every play's numbering already imported, label unset.

## Round trip (docs/backlog.md, ida-y-vuelta.html)
- Verse/prose "mixed" threshold (q23 follow-up): 61 plays labelled `verso` in our corpus copies until the project answers.
- Original cast (`characters.actor`) is stored and exported but printed nowhere: waits on q28.
- Backlog item "Found by the corpus round trip": `sp@who` naming no cast role (2,508 refs, 29 plays) and `stage@n` (376) still lost on import.

## TOP 3 FEATURES (clear to implement, verified in code)
1. **Emphasised "aside" refused**: FileMaker's EMOTHE0398 cannot import as-is (it was imported with italics dropped); `<<aside>>` makes `asides_well_formed?` fail. `lib/playcode/play_content/inline_markup.ex:495-497` and `element.ex:296-308`. Fix: the marker test ignores `<<…>>`.
2. **Marking complete/draft is not logged**: nobody can tell who published EMOTHE0439. `lib/playcode_web/live/admin/play_detail_live.ex:111-130` calls `update_play_from_form/2` with no `LiveHelpers.log_activity` (the delete handler at line 100 has one). Fix: log it.
3. **Word importer reads `document.xml` with regexes**: text split by `<w:tab/>`/`<w:br/>` is missed, and only 5 entities are decoded. `lib/playcode/import/word_parser.ex:17-49`. Fix: parse with Saxy.

Not listed (wait on a choice): Folio search/notes (two options), import-page warnings (fill or drop column, `import_live.ex:172` still `[]`), import page preview written twice.

**Stale in backlog**: none found among the candidates checked.

## ONE SPEED WIN
- `lib/playcode/export/static_site.ex:433`: `refresh_assets` reads and regex-rewrites every `*.html` of the site (`Path.wildcard` over the whole tree) whenever the assets' fingerprint moves, on top of the rebuild.
- Change: cheap pre-check, `String.contains?(html, "?v=#{stamp}")` skip before `Regex.replace`; or (simpler) drop the pass for pages the same Generate rewrites anyway, since built pages already carry the new stamp.
- Gain: only on asset-only deploys; avoids a binary-wide regex per page, likely seconds to a minute of the shared CPU's time over a few thousand pages. Measure: time `refresh_assets/2` on a built `_site`. Unverified: I read, did not run, and found no Repo-in-loop in `edition.ex`.
- Risk: low; a page that misses the stamp serves a stale stylesheet, so keep `static_site_test.exs` covering it. (No previous brief branch found to avoid repeating.)
