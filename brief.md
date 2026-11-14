# Playcode brief 2026-11-14 (8adc0d1)

Focus: none set.

## 19 of 72 questions open
**Easiest** (yes/no or one fact)
- [7](docs/stakeholder/preguntas.html#q7) The Rover's 40 hidden stage directions: show them? one yes/no.
- [28](docs/stakeholder/preguntas.html#q28) Show the original cast's actors? one yes/no, 1 play.
- [34](docs/stakeholder/preguntas.html#q34) Are two epilogues part of the play? two plays, the manual decides.
- [72](docs/stakeholder/preguntas.html#q72) Link translations to the original's RoleCall chart? yes/no.
- [54](docs/stakeholder/preguntas.html#q54) English names of the relation kinds: a short list to correct.

**Most important**
- [66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays wait; backlog C1.
- [68](docs/stakeholder/preguntas.html#q68) Word before a cited number: touches every play's numbering.
- [69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays: finishes the Numbering section.
- [14](docs/stakeholder/preguntas.html#q14) Nine plays with a web edition but no TEI file: publishing gap.
- [57](docs/stakeholder/preguntas.html#q57) Plays held without a text: decides the relations work (q53-56 follow).

## Round trip (backlog, ida-y-vuelta)
- Asides: play page and site mark them less than the downloads (note 37).
- Verse/prose limit (q23 follow-up): 61 plays "mixed", file copies still say `verso`.
- Original cast (q28): stored and exported, printed nowhere.
- Cells short of "yes": split verses/indentation/asides, HTML typed into text (4 plays), editors' roles in HTML/PDF.

## Top 3 features
1. EMOTHE0443 `<set>` closing note is dropped: the last front-matter note lost; small, import fix.
2. Folio words searched and their notes listed while the switch is off: hits land on invisible lines.
3. Front matter prints header texts through `escape/1`: `<<…>>` shows once a header has italics.
(Skipped: site deploy waits on UV; numbering, prologues, relations wait on the project.)

## Speed win
- `lib/playcode/export/static_site.ex:600`: `original || Edition.load(parent.id)` rebuilds the whole original Edition for every translation's compare page.
- Change: when the build already holds the original, or builds several translations of it, load it once and pass it in; delete the fallback load where callers can supply it.
- Gain: an original with N translations (Hamlet, Celestina) is loaded N times; one load is many queries plus the text walk. Measure with `:timer.tc` around `Edition.load/1` over a Generate.
- Risk: low-medium; memory holds one more edition, and a stale original would show if the change tracking (`relatives/3`) is bypassed. Differs from the previous brief (statistics lookups).
