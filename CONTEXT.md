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
Where and when the play takes place, given with the cast list ("Scene: An Italian
Court."). Not a paratext.
_Avoid_: setting (a place's role), circunstancia de la acción

**Kind**:
What a paratext is: a dedication, a licence to print, an editor's introduction. The kind
decides whether it is an editorial text. The file gives it; the editors correct it when
the file is wrong.
_Avoid_: section type, type

**Before the text / after the text**:
Where a paratext stands.
_Avoid_: front and back (where the TEI file puts it), place (a place is in the gazetteer)

### The critical apparatus

**Variant**:
A place in the text where the witnesses differ, and what each of them reads there: a TEI
`<app>`. Readers see an asterisk after the word, which opens the readings. It is kept as a
note of type `variante`, numbered apart from the notes (the notes' 1, 2, 3; the variants'
own 1, 2, 3), and a play's switch hides them all. Not `variantes`, which is the type of
three ordinary notes.
_Avoid_: apparatus note, textual note, note (a note glosses a word; a variant lists what the
witnesses read)

**Folio passage**:
Words only the 1623 Folio prints, in Hamlet, whose base text is the Second Quarto. Kept as
a `<folio>…</folio>` marker in the text it sits in (a TEI `<app type="folio">`), hidden by
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
