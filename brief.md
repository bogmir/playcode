# Playcode brief 2026-11-23 (main @ d976f2c)

## 18 of 72 questions open ([preguntas](docs/stakeholder/preguntas.html))
Easiest 5:
- [q7](docs/stakeholder/preguntas.html#q7) Rover's 40 hidden stage directions: a yes/no on a switch
- [q13](docs/stakeholder/preguntas.html#q13) Jodelle slip on 11 witnesses: one name to give
- [q70](docs/stakeholder/preguntas.html#q70) Character genders: pick the words (woman/man/X)
- [q71](docs/stakeholder/preguntas.html#q71) Where genders show: tick boxes
- [q72](docs/stakeholder/preguntas.html#q72) Translation links to the original's RoleCall chart: yes/no

Most important 5:
- [q66](docs/stakeholder/preguntas.html#q66) 45 prologues on the wrong side, 33 plays: unblocks backlog C1
- [q69](docs/stakeholder/preguntas.html#q69) Renumber 16 hand-numbered plays: unblocks the Numbering section
- [q53](docs/stakeholder/preguntas.html#q53) Which "version" plays are later versions: gates the Relations design (with q54-56)
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: every play's numbering is set, only the label is missing
- [q14](docs/stakeholder/preguntas.html#q14) Pyrame et Thisbé editions and 3 plays with no text anywhere: corpus completeness

## Round trip (backlog; ida-y-vuelta.html cells not scanned)
- Verse/prose threshold (q23 follow-up): 61 dev plays are "mixed"; corpus copies still say `verso`
- Original cast (q28, open): `characters.actor` is stored and exported, printed nowhere
- Hamlet v. 2632 is exported as 3 stage directions against 1 in the source
- `sp@who` naming no cast role: 2,508 references in 29 plays lose their character and statistics

## Top 3 features (clear, verified in code)
1. **Marking a play complete or draft is not logged** - EMOTHE0439 went live on 2026-11-17 and nothing says who did it. `play_detail_live.ex:110` `set_status` calls `Catalogue.update_play_from_form/2` (`catalogue.ex:327`), which logs nothing, while delete logs at `:99`. Fix: `LiveHelpers.log_activity` on success.
2. **An emphasised "aside" is refused** - `<emph>aside</emph>` becomes `<<aside>>`, and `InlineMarkup.holds?/2` (`inline_markup.ex:422`) is a `String.contains?` for `<aside>`, so `Element.changeset` (`element.ex:293-306`) rejects the whole file (FileMaker EMOTHE0398). Fix: the marker test ignores `<<…>>`.
3. **Word importer reads document.xml with regexes** - `<w:t>` text split by `<w:tab/>`/`<w:br/>` is lost and `unescape_xml` (`word_parser.ex:17`) skips numeric entities. `word_parser.ex:42-51`. Fix: parse with Saxy.

Stale in backlog (owner to edit):
- Round trip says q23 "stays open", but q23 is answered in preguntas.html (parsed: not among the 18 open)
- Relations section says "53-57 open"; q57 is answered

## Speed win
- `lib/playcode/import/tei_import.ex:777-812` (`write_settings`) and `:582-585` (`place/1`, one per performance): `Repo.get_by` for the place, plus a `PlayPlace` lookup, per row. Read each slug once into a map before the loop: 2 queries saved per setting and 1 per performance.
- Gain: small (about 0.2 ms per query, plays hold a few settings and tens of performances). Measure with `mix playcode.import.tei --force` on a play with many performances and Ecto query counts; this is not a Generate cost, so test it before committing to it.
- Risk: low, but keep the `origin` branches (manual/tei) as they are.
- Checked and not proposed: `list_plays` repeated in Generate (already measured at 40-60 ms, `static-site-improvements.md:197`). No better hotspot found in the 8 files read; the Generate cost is per-play page rendering.
