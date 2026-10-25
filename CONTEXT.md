# Playcode

The platform behind EMOTHE and ARTELOPE: early modern European plays, their text and what
was printed around it, edited by researchers and published from one TEI copy.

## Language

### The play and what surrounds it

**Text**:
The play itself: its divisions, the speeches in them and the stage directions.
_Avoid_: body, content

**Division**:
A part of the text: an act, a scene, a spoken prologue or epilogue.
_Avoid_: section

**Prologue**:
A division spoken before the first act. A prologue printed for readers ("Al lector",
"Prólogo [a la edición de 1635]") is a paratext; where the line falls is question 31.

**Epilogue**:
A division spoken after the last act. The Rover and El hombre a la moda give theirs after
the text as a paratext; whether they are divisions is question 34.

**Paratext**:
A text that stands before or after the text without being part of it: one printed with
the play in its early edition or manuscript (a dedication, an address to the reader, a
licence to print, a performance notice, a colophon), or an editorial text.
_Avoid_: editorial note, section, front matter, back matter

**Editorial text**:
A paratext written for this edition by its editors or translators: an introduction, a
note on the digital edition, a translator's note, an appendix.
_Avoid_: editorial note, apparatus (the critical apparatus is the variants), note

**Licence to print**:
A paratext authorising the printing: a licence, a privilege, an approbation.
_Avoid_: licence (alone: the edition's licence is its terms of use)

**Scene of the action**:
Where and when the play takes place, usually given with the cast list ("Scene: An
Italian Court."). Not a paratext, but it stands in the outline as one does.
_Avoid_: setting (a place's role), circunstancia de la acción

**Kind**:
What a paratext is: a dedication, a licence to print, an editor's introduction. The kind
decides whether it is an editorial text. The file gives it; the editors correct it when
the file is wrong.
_Avoid_: section type, type

**Before the text / after the text**:
Where a paratext or a cast list stands: before the first act, after the last, or between
two. It follows from the item's place in the outline.
_Avoid_: front and back (where the TEI file puts it), place (a place is in the gazetteer)

**Outline**:
Everything in a play in the order it is read: the paratexts, the scene of the action, the
cast lists and the divisions, each where it stands. One order, the same in the admin's
Structure tab, the TEI file and every page.
_Avoid_: structure (the admin tab that edits it), table of contents (a page's navigation)

**Cast list**:
A list of the play's people with its own heading and place in the outline: before the
text, between two acts, inside an act or after the text. A play may have several; one
person may be in several lists.
_Avoid_: dramatis personae (one list's heading), elenco (the file's word for its division)

**Cast list entry**:
One line of one cast list: a person as that list names and describes them ("BELTRANICO,
que es LUCRECIA"), perhaps under a group heading ("Women"), or a line naming no one who
speaks ("Servants and attendants"). A character is named as its first entry names it.
_Avoid_: character (the person the speeches point at, whatever each list calls them), role

**Aside** (*aparte*):
Words a character speaks for the audience, or for one other character, unheard by the rest of the stage. One aside may run over many verses (Clotaldo's in *La vida es sueño*, vv. 395–468) and on into another speaker's speech.

**Piece** (of an aside):
The part of an aside inside one verse or paragraph, TEI's `<seg type="aside">`, which cannot cross a line. The files number each piece within its aside (`es-0412-seg02`).
_Avoid_: segment, fragment (a fragment is a split verse's part)

### The critical apparatus

**Variant**:
A place in the text where the witnesses differ, and what each of them reads there: a TEI
`<app>`. Readers see an asterisk after the word, which opens the readings. It is kept as a
note of type `variante`, numbered apart from the notes (the notes' 1, 2, 3; the variants'
own 1, 2, 3), and a play's switch hides them all. Not `variantes`, which is the type of
three ordinary notes.
_Avoid_: apparatus note, textual note, note (a note glosses a word; a variant lists what the
witnesses read)

**Critical edition**:
A play with variants, or an appendix headed "Critical Apparatus" after the text (decided by
Playcode, 2026-10-19; no file marks one): EMOTHE0010, 0187, 0435, 0460, 0530, 0551, 0560
and 0644. Its downloads print its witnesses; with its variants switched off, they do not.
_Avoid_: scholarly edition, variorum

**Folio passage**:
Words only the 1623 Folio prints, in Hamlet, whose base text is the Second Quarto. Kept as
a `<folio>…</folio>` marker in the text it sits in (in the TEI file an `<app type="folio">`
when it is inside one element; one that crosses elements is written in the file's own marks
until question 37 settles a TEI form), hidden by
default on the play page and the site (the downloads print it) and shown in grey, between
small F's, by a "Folio interpolations" switch that is not the variants'. Not a variant, which
lists what several witnesses read at one place.
_Avoid_: Folio interpolation (the switch's own label), Folio-only text, addition (the Q4
Additions of *The Spanish Tragedy* are another thing)

**Reading**:
What one witness, or several together, give at a variant: the witnesses' sigla, the text
they read and, if the editor has one, a comment on it. A variant has one or more.
_Avoid_: variant (the whole entry), version

**Lemma**:
The reading the edition follows, a TEI `<lem>`: at most one to a variant, and first. The
variant's other readings are the `<rdg>`s.
_Avoid_: edition's reading (the editor's own label for the checkbox), base text

**Siglum**:
The short name of a witness or of a modern edition: `P3`, `H`, `Dyce`. A reading names its
witnesses by their sigla written with a `#` (`#H #P3`); readers see each siglum with what it
names ("H (Hartzenbusch, 1860)"), where Playcode knows.
_Avoid_: abbreviation, id

### Places

**Historical state** (*estado histórico*):
The state a place belonged to at the time of a play — Castilla, Reino de Inglaterra,
República romana — or the wider area the editors name when they name no state (Península
itálica). A place in the gazetteer like any other; a play's link names it.
_Avoid_: polity, then part of, país histórico

### Performances

**Performance** (*representación*):
One staging of a play recorded by a source — a date, a venue, a company, a cast. The play
page's "Performances".
_Avoid_: historical performance in the interface (all of them are), representación antigua

**Company** (*compañía*):
Who staged it, a record shared by every performance it gave.

**Venue** (*lugar de la representación*):
Where, as the source names it ("The Rose playhouse"); text, not a place. Its **venue type**
(*circunstancia escénica*) is one of eight. The town is the performance's place, from the
gazetteer.
