# Word File Import for Annotated Plays (Premarcación)

## Problem

Researchers working with plays not yet in TEI XML format use Word documents where each line is annotated with codes indicating its type (verse, stage direction, speaker, etc.). Currently, the only import path is TEI XML. Researchers need a way to import these annotated Word files and then assign text chunks to characters in a review phase.

## Premarcación Tag Reference

Based on "Instrucciones edición digital en EMOTHE 2020" and example files.

| Tag | Meaning | Maps to |
|-----|---------|---------|
| `{e}` | Scene boundary ("Escena 1", "1.1", "FIN") | Division (type=escena) |
| `{ac}` | Stage direction (acotación) | Element (type=stage_direction) |
| `{ap}` | Aside marker (aparte) | Sets `is_aside=true` on the speech |
| `{p}` | Speaker name (personaje) | Element (type=speech), `speaker_label` |
| `{v}` | Complete verse line | Element (type=verse_line) |
| `{ti}` | Split verse — initial part (parte inicial) | Element (type=verse_line, part="I") |
| `{tm}` | Split verse — middle part (parte media) | Element (type=verse_line, part="M") |
| `{tf}` | Split verse — final part (parte final) | Element (type=verse_line, part="F") |
| `{pr}` | Prose | Element (type=prose) |
| `{m}` | Stanza/strophe boundary (estrofa) | Element (type=line_group) |
| `<<text>>` | Italic text | `rend="italic"` or wrap in markup |
| `((text))` | Aside text within speech | Content within `is_aside=true` scope |

Tags are **case-insensitive** (`{P}` = `{p}`, `{PR}` = `{pr}`, etc.).

### Key parsing rules

1. **One paragraph = one element** (mostly). A `{v}` line is one verse. A `{pr}` paragraph may span multiple Word lines but is one prose block.
2. **Multiple tags per line**: `{p} JOHN {pr} Hello` = speech with speaker "JOHN" + prose content "Hello".
3. **Act headings are NOT tagged** — they appear as plain text like "Act 1", "JORNADA I", "ACTO PRIMERO". In the current FileMaker workflow, each act is copied separately. For our import, we detect these as act boundaries.
4. **`{e}` always on its own line** — marks scene starts.
5. **No blank lines** between elements.
6. **Speaker extraction**: After `{p}`, the speaker name runs until the next tag. E.g., `{p} JOHN {pr} text` → speaker_label="JOHN", content="text".
7. **Aside in prose**: `{ap}` marks the speech as aside; `((text))` delimits the aside content within the prose.
8. **Stage direction inside speech**: When `{ac}` appears mid-line (after `{p}`), it creates a separate stage_direction element.
9. **Inline stage direction relocation**: If a stage direction appears at the end of a verse/prose line in the original, researchers move it to a new line with `{ac}`.
10. **Speaker names unabbreviated**: The EMOTHE convention expands abbreviated speaker names to full form.

### Example parse (from Ejercicio para premarcar)

```
{p}FEBO  {v}Será remedio casarte.        → speech(speaker="FEBO") > verse_line("Será remedio casarte.")
{p}RICARDO  {v}Si quieres desenfadarte,  → speech(speaker="RICARDO") > verse_line(...)
{v}     pon a esta puerta el oído.        → verse_line (continues in current speech)
{p}DUQUE  {ti}¿Cantan?                   → speech(speaker="DUQUE") > verse_line(part="I")
{p}RICARDO         {tm}¿No lo ves?        → speech(speaker="RICARDO") > verse_line(part="M")
{p}DUQUE                            {tf}¿Pues quién  → speech(speaker="DUQUE") > verse_line(part="F")
{ti}     vive aquí?                       → verse_line(part="I", continues in current speech)
```

## Answers to Open Questions

### Annotation format
1. Tags are curly-brace codes at the start of text segments: `{v}`, `{p}`, `{ac}`, `{pr}`, `{ti}`, `{tf}`, `{tm}`, `{ap}`, `{m}`, `{e}`.
2. Act boundaries: **not tagged with `{e}`**. They appear as plain text ("Act 1", "JORNADA I"). Scene boundaries use `{e}`. In the current FileMaker workflow, each act is copied and pasted separately.
3. Codes are placed inline in the text, at the start of each structural segment within a paragraph.

### File structure
4. Not exactly one paragraph per line. The unit is the paragraph. A verse speech with three verses has three paragraphs each starting with `{v}`. A long prose speech is a single paragraph starting with `{pr}`.
5. The entire premarcado text is in a **single file**. In FileMaker, acts are copied separately, but in our import we handle the whole file at once.

### Metadata
6. Word files do **not** contain metadata. The researcher creates the play first (title, author, code, language) via the admin UI, then imports the premarcado content into that existing play.

### Characters
7. The dramatis personae can be created **after** import. However, until characters are created and speech-character associations are made, the play cannot be fully encoded.
8. Speaker names are in the Word file as plain text after `{p}`, e.g., `{p} JOHN {pr} Hello`. These become `speaker_label` on the speech element, but `character_id` remains null until the review phase.

### Line numbering
9. Line numbers are **auto-generated** on import. The premarcado files don't include numbering.

## Proposed Workflow

1. **Create play** via `/admin/plays/new` (title, author, code, language)
2. **Import content** from play detail page (`/admin/plays/:id`) — upload `.docx`, parser populates divisions/elements
3. **Review characters** — new bulk character assignment page at `/admin/plays/:id/character-review`

## What needs to be built

| Component | Description | Effort |
|-----------|-------------|--------|
| **Word parser** (`lib/playcode/import/word_parser.ex`) | Parse `.docx` (ZIP + XML), map premarcación tags to elements | Medium |
| **Import content UI** on play detail page | Upload `.docx` into existing play | Small |
| **Bulk character assignment UI** | `/admin/plays/:id/character-review` — create characters, assign to speeches | Medium-Large |

### No schema changes needed

The existing DB schema fully supports this:
- `elements.speaker_label` stores the name from `{p}`
- `elements.character_id` is nullable, set during review phase
- `elements.part` stores "I"/"M"/"F" for split verses
- `elements.is_aside` for aside detection
- `divisions` support all needed types (acto, escena, jornada, etc.)
- `elements.rend` for italic markers

### Technical approach

- `.docx` files are ZIP archives containing `word/document.xml` — Elixir can unzip and parse the inner XML with the same Saxy library used for TEI
- The parser creates divisions + elements in a DB transaction (same pattern as `tei_import.ex`)
- The bulk character assignment page lists all speeches grouped by division, with multi-select batch assignment

## Example files

- `docs/Instrucciones edición digital en EMOTHE 2020.docx` — full premarcación instructions
- `docs/Ejercicio para premarcar.docx` — exercise with unmarked + marked versions
- `docs/Bartholomew Fair_Marcado Final 20240122_jtp.docx` — real English play (prose-heavy, uses `{P}`, `{PR}` uppercase tags)
