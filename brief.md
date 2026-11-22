# Playcode daily brief, 2026-11-22 (d976f2c, main)
Current focus: none.

## Questions: 18 of 72 questions open
Links: `docs/stakeholder/preguntas.html#qN`.

**5 easiest**
- q70 Genders a character may have: Woman/man/X proposed, tick a box.
- q72 Translation links to original's RoleCall chart: yes/no.
- q71 Where readers see gender: tick one or more places.
- q68 Word before a cited number ("v." today): one word.
- q7 The Rover's 40 hidden stage directions: show them? Yes/no.

**5 most important**
- q66 Prologues on the wrong side: 45 texts in 33 plays; blocks backlog C1 and a file correction.
- q69 Recount 16 hand-numbered plays: a yes lets Manual be switched off and Generate.
- q53 Which "version" plays are originals: blocks the relations design (54-56 follow) and the family migration.
- q28 Show the original cast's actors: printed nowhere today; a Round trip item waits on it.
- q50 Two split-verse parts and a stage direction: corpus copies stay uncorrected.

## Round trip
- Where verse and prose ends (q23 follow-up): our 10%/90% rule is live; 61 plays still labelled `verso` in the corpus copies.
- Original cast (`characters.actor`) is written to TEI but printed nowhere (q28).
- ida-y-vuelta.html: 15 cells "no" and 10 "part" in total; details in the table.

## Top 3 features (clear to implement, verified in code)
1. **Log marking a play complete/draft** - `set_status` leaves no trace: EMOTHE0439 went live on 2026-11-17 with nobody named. `play_detail_live.ex:110` calls `Catalogue.update_play_from_form/2` (`catalogue.ex:327`); line 99 shows `LiveHelpers.log_activity` used for delete. Fix: log an "update" entry with the new status.
2. **Emphasised "aside" in a stage direction refuses the whole file** - FileMaker's EMOTHE0398 (*The Roman actor*) cannot import with its italics. `element.ex:293` `validate_aside_markers/1` sees `<<aside>>` as the marker. Fix: ignore text inside `<<…>>` in the marker test.
3. **Word importer reads `document.xml` with regexes** - `<w:t>` text split by `<w:tab/>`/`<w:br/>` is lost and only five entities decode. `word_parser.ex:45-48` (`Regex.scan`), `:17` `unescape_xml/1`. Fix: parse with Saxy like `TeiParser`.

Stale in backlog: none found among the items checked. Skipped as waiting on a choice: Folio words in search (either/or), import validation warnings (fill or drop).

## One speed win
- `lib/playcode/export/static_site.ex:646` (with `relatives/3`, `:503`): a sibling rebuilt for a changed translation runs `Edition.load(parent.id)` itself when `original` is nil, so n siblings load the original n times.
- Change: load the original once per family in `relatives` and pass it in, as `build_family/4` does (`:465-468`).
- Gain: one full `Edition.load` (the heaviest read) saved per extra sibling; matters only for originals with many translations (see the ponytail at `:498`). Measure by timing a Generate after touching one translation of such a play.
- Risk: low, but check `families/1` first: siblings may already be grouped under their parent when it is in the batch.
