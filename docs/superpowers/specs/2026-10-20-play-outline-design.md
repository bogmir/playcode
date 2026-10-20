# The play's outline: cast lists, paratexts and acts in one order

**Status:** designed 2026-10-20, from the team's answers to questions 42 and 43 and a
brainstorming session the same day. Plan: `../plans/2026-10-20-play-outline.md`.
Words as in `CONTEXT.md`; this design adds **outline** and **cast list entry** to it.

## Why

Six files have more than one cast list, and Playcode reads them as one: every role becomes a
character, the play page prints all of them under each list's heading (*El galán Castrucho*
shows its 42 roles three times), and the file Playcode writes has one list. The team settled on
2026-10-20 what each list is (`docs/stakeholder/preguntas.html`, questions 42 and 43):

- *Le Malade imaginaire* (EMOTHE0714) keeps three distinct lists, *La Tragédie espagnole*
  (EMOTHE0112) four. TEI allows several `castList`s one after another, and a `castList` needs no
  `div` around it: its `head` goes inside.
- *'Tis Pity She's a Whore* (EMOTHE0283) is one list, "Women" a group inside it (`castGroup`
  with its `head`). Its second list was a FileMaker workaround.
- *El galán Castrucho* (EMOTHE0555) puts each list inside its act, as its source does (Biblioteca
  Virtual Miguel de Cervantes). The people of the second and third lists are the first list's:
  they keep its identifiers (ESCOBARILLO2 and ESCOBARILLO3 go), and each list gives them its own
  description ("Beltranico, que es Lucrecia" in act 1, "Lucrecia, en figura de Beltranico" in
  act 3).

Behind the cast lists sits a wider fault: **Playcode has no single order for what makes up a
play.** The parser reads the front, body and back in file order onto one position scale
(`TeiParser.front/1`, `body/2`, `back_matter/2`), but from there each kind keeps its own:

- the admin reorders paratexts among themselves (`Catalogue.reorder_paratexts/2` renumbers them
  from 0), characters among themselves, and divisions not at all;
- the export writes by kind, in a fixed order: title page, every front paratext, the cast list,
  the scene of the action, the performances (`TeiXml.build_front/6`);
- the pages print by kind too (`PlayLabels.split_paratexts/2`: paratexts above the cast list, the
  scene after it).

So a file's order is lost on the way through Playcode: 7 head titles that stand after the cast
list come back above it (question 32, decided "where the file puts it" and still not built), and
*Egle*'s scene of the action, before its cast list in the file, prints after it. The owner's
rule for this project: **what an editor sees in the admin is what the file says**, in the same
order, and an editor can place a cast list, a paratext or a division wherever they wish.

## What gets built

### The outline

A play's **outline** is one ordered sequence of its top-level items: paratexts, the scene of the
action, cast lists and the body's divisions (acts, prologues, interludes, inductions, dumb
shows, epilogues…). An act's children are its scenes and its cast lists, in their own order.
Every item at one level shares one position sequence; nothing is ordered by kind.

The Structure tab of the content editor becomes the outline:

- every top-level item in order, each draggable to any place among them; an act's scenes and
  cast lists draggable within the act;
- "Add Act" becomes **"Add division"**, with a type choice that includes Cast list beside the
  division types; "Add Scene" becomes **"Add subdivision"**, its choices Scene and Cast list;
- a paratext is added from the outline too, into the place chosen; its text is edited in the
  Paratexts tab, which keeps its form and loses its drag handles, since order lives in one place;
- a cast list has no scenes and no lines: no "Add subdivision", no "Edit content".

The performances stay at the end of the front, outside the outline: they are records about the
play, not reading matter (our call).

### Where each item goes in the file

The position decides the encoding; no item stores whether it is before or after the text. At
each level the rule is the same: TEI lets free-standing content open a division, but once that
level's numbered divisions start, only divisions of that rank follow. So:

| Where the item sits | Written as |
|---|---|
| Top level, before the first body division | in `<front>`: a paratext as `<div type="kind">`, the scene as `<set>`, a cast list as `<div type="elenco"><head/><castList/></div>` |
| Top level, between two body divisions | in `<body>`: `<div1 type="kind">` for a paratext, `<div1 type="elenco">` holding the `castList` for a cast list |
| Top level, after the last body division | in `<back>`: as in `<front>`, before the bibliography |
| Inside an act, before its first scene | a bare `<castList><head/>…</castList>` (question 43's choice) |
| Inside an act, between or after scenes | `<div2 type="elenco">` holding the `castList` |

The corpus already uses `div1` for what is not an act (`prologue` 38 times, `epilogue` 24,
`induction` 12, `interlude` 11, `dumb_show` 5), so a `div1` of another type between acts is the
files' own practice. The import reads every row of this table back to the same place, so
export, import and the outline agree by construction. `play_paratexts.back` goes: whether a
paratext is after the text follows from its position. The title page always opens `<front>`.

A play with no body division puts every top-level item in `<front>`.

### Cast lists

A cast list is a division of type `elenco` (as today, where the one list is an empty `elenco`
division and the characters hang off the play). What changes is that a list holds its entries.

A **cast list entry** is one line of one list, at a position, holding what that list prints:

- its **name** and **description**, exactly as the list gives them. In 0555 one person is
  "BELTRANICO" (described "que es LUCRECIA") in act 1, "LUCRECIA" in act 2 and "LUCRECIA" (described
  "en figura de BELTRANICO") in act 3; "EL GENERAL DEL EJÉRCITO" in act 1 is "EL GENERAL" in act 2;
  act 2 brackets "[PRADELO" … "soldado]". An empty description means none in this list; nothing is
  inherited from another list;
- a **group heading**, empty for most: consecutive entries with the same one are written as one
  `castGroup` with that `head` (0283's "Women");
- the **character** it names, or none (below).

A character is the person the speeches point at: one row with its identifier, actor and hidden
flag, and a name, its first entry's, for wherever Playcode names a speaker (the speaker
pickers, the statistics). Its first entry in outline order writes `<role xml:id="…">`; every
later entry writes `<role corresp="#…">`. Each entry writes its own name and `roleDesc`, so
dragging act 2's list above act 1's moves only the declaration, at the next export, and copies
no text. On import a role with `xml:id` makes a character and its entry, and a role with
`corresp` makes an entry for the character it names.

**An entry may name no character.** 32 files list a role with neither `xml:id` nor `corresp`,
one or two each ("Servants and attendants"), and no speech points at any of them; EMOTHE0404's
front list is 17 such names. Today the parser makes each a character whose identifier is its
name, which the export writes as an `xml:id` with spaces and commas, not a valid one. They
become entries naming no character, printed in their list and written back as the file had
them, `<role>` with no id. Those 32 plays lose one or two characters that never speak from their
character count.

A character always has at least one entry. **Deleting a cast list** is refused while it holds
the only entry of a character who speaks, naming them; otherwise it deletes its entries and any
character left with none, and the confirmation says how many. 0404's front list deletes cleanly.

The Characters tab shows one section per cast list, in outline order, each under its heading
(an act's list labelled with its act). Characters are dragged within and between lists. "Add an
existing character" puts a character already in another list into this one, with its own
description; nobody types an identifier.

`ana="grupo"` (a role that is a group: soldiers, servants; 560 roles) is a different thing and
stays with the character reconciliation, S6.

### Reading and printing

The play page, the downloads (HTML, PDF, EPUB), the published site and the comparison page
print the outline in order: each paratext, scene of the action and cast list where it stands,
each cast list with only its own entries, a list inside an act at the head of that act, or
between its scenes. Each cast list gets an entry in the play page's navigation and the
published site's Contents, as the paratexts after the text have.

A performance whose cast comes from the cast list (`corresp="#castlist"`, The Way of the World)
takes it from the play's first cast list in outline order.

`/api/v1` keeps its shape (`lib/playcode_web/controllers/api/play_controller.ex`): a paratext's
`back` is worked out from its position, a character's `description` is its first entry's, and
cast lists are not added to it.

### The files we correct

In our copies (`doc/tei_corpus/` and the fixtures that hold the same plays), as with
*Mariamne* (question 8); the team gets the list of changes for theirs:

- **EMOTHE0283**: one `elenco` with "Women" a `castGroup`.
- **EMOTHE0555**: the second and third lists move inside their acts as bare `castList`s; their
  people point at the first list's roles by `corresp`, keeping the name and description their act
  gives them;
  SOLDADOS (act 2's list only) and ACOMPAÑA (act 3's only) keep their own ids there.

0112 and 0714 need no change. EMOTHE0404 imports both its lists, the front 17 names and the back
"[EDITORIAL CASTLIST", each where its file puts it, as emothe.uv.es prints both; if the team's
answer to question 29 leaves the 17 out, an editor deletes that list in the outline. EMOTHE0718's
back list, all hidden, becomes its cast list (question 29, decided).

## Goals

- One order per play, the same in the admin, the file, the import and every page.
- Several cast lists, each with its own entries, heading and place, groups inside a list, and
  one character in several lists with a description per list.
- The four plays of questions 42 and 43, and the two of question 29, come back from their files
  whole: the "A cast list per act or part" row of the round-trip page turns to Yes.
- Question 32 is built by the same change: a paratext prints where its file puts it.

## Non-goals

- Paratexts inside an act; nothing in the corpus has one.
- A paratext in verse (question 30's sonnet): its own item in the backlog.
- `ana="grupo"` roles (S6).
- Where the performances stand: fixed at the end of the front.

## Anti-goals

- **A place in the outline the file cannot hold**, or a file order the outline cannot show.
- **Any order decided by kind** in the export or a renderer once this is built.
- **Losing a hand-added paratext on re-import.** Its row survives as today (`origin`), and its
  place too: it keeps its position number among the re-imported items.
- **Identifiers typed by hand** to say two entries are one person.
- **A second ordering for one thing**: the Paratexts tab and the Characters tab order nothing
  the outline orders.

## Constraints

- TDD, tested through the outermost API: the outline through the content editor LiveView, the
  file through `roundtrip/1`, `outline/1` and the XML helpers in `test/support/import_helpers.ex`.
- `test/playcode/complete_copy_test.exs`: its rarer play gains several lists, a list inside an
  act before its scenes and one between them, a list and a paratext between acts, a `castGroup`,
  a character in two lists with a second description, a cast list after the text. The new table
  joins its table check.
- The new table has a `play_id` and its rows show on the play's pages: it needs the
  `play_row_changed()` trigger (`content_version_test.exs`).
- Every produced file validates against the TEI schema (`mix test --include slow`), the `div1`
  of a cast list or paratext between acts and a `castList` inside an act included.
- A browser id is resolved through a getter scoped to the play (a list, an entry), as every tab
  does.
- `docs/tei-mapping.md`, `docs/schema.md`, `CONTEXT.md`, the round-trip page's rows and notes,
  and `docs/backlog.md` (*A second cast list*, *A cast list after the text*, *A paratext after
  the cast list* move to `docs/history.md`) change with it.

## Left to the builder

- The table's name and columns for cast list entries, and how `characters.position` and
  `characters.description` give way to the entries'.
- The migration: an entry for every existing character in its play's `elenco` division (one made
  where a play has characters and none), and one position sequence per play from what is stored.
  Production's plays get their files' order back from the next TEI re-import, as earlier changes
  did; a play whose paratexts were dragged by hand keeps that order.
- How the import tells a `div1` between acts that is a paratext from one that is a division (a
  `prologo` is both a paratext kind and a division type): Playcode writes a paratext there with
  only `head` and `p`, so a `div1` with no speech, verse or stage direction reads as one. Sweep
  the corpus before relying on it.
- How the scene of the action is written where `<set>` cannot stand (between acts): the files'
  own `circunstancia_accion`, which the import already reads as the scene, is the obvious form.
- The drag mechanics, reusing the paratexts' hook; the type choices' labels.
- How the Word import, which makes one `elenco` division and its characters, makes their entries.
