# A Notes tab in the play admin

Changing a note today means finding its line in Content, opening that line's modal and its
notes section. With about 3,800 notes in the dev corpus that does not scale. This tab lists a
play's notes and edits them where they are listed. Adding a note stays in Content, where the
line is chosen. Agreed 2026-10-10, without the bulk type change.

## The page

`/admin/plays/:id/notes`, `PlaycodeWeb.Admin.PlayNotesLive`, `{:ensure_can, :edit_content}`.
A **Notes** tab in the play context bar, after Content, always shown (a play with no notes
says so and points to Content).

- **Each note, in reading order** (`Note.with_anchors/1`, the numbering the public page
  shows): number, type label, glossed word (`Note.glossed/2`), where it is (division, scene,
  line number: the public Notes view's place, now one shared function), the **context**
  (the plain text it hangs on, the note's place marked by its number, cut to about 60
  characters before and 40 after) and its text, paragraphs kept.
- **Finding:** a type select (the play's types, `PlayLabels.note_type_key/1`), a search over
  the note's text and term (accent- and case-blind, `Bibliography.fold/1`) and "Without a
  term". The count reads "N of M notes" while filtered.
- **Editing in place:** Edit turns the row into a form: type, the word it follows (the word
  picker of the content editor's note form, `NotesComponent.offset_options/2`), term, text.
  Save goes through `PlayContent.update_note/2` and is logged as the content editor logs a
  note (`resource_type: "note"`). Cancel restores the row. One row at a time.
- **A type the select does not list** (`latinismo`, `falta_tipo`, … 11 types in the dev
  corpus) is offered as itself, selected, so saving a note's text does not drop its type.
  `PlayLabels.note_type_options/1` takes the current type. The content editor's note form
  had the same loss and uses the same function.
- **Delete**, with a confirmation, through `PlayContent.delete_note/1`, logged.
- **Open in Content:** a link to `/admin/plays/:id/content?element=<id>` (or `division=`),
  which opens that line's (or heading's) modal, its notes section included. The content
  editor reads the parameter on mount through its scoped getters; an unknown id opens
  nothing.
- **Ids from the browser** are resolved with `PlayContent.get_note/2`, scoped to the play
  (nil for another play's note, a deleted one or a malformed id); the list then reloads with
  `LiveHelpers.put_gone_flash/1`.
- **Live:** the page subscribes to the play's topic (`PlayContent.subscribe/1`) and reloads on
  `{:play_content_changed, _}`, keeping an open form while its note still exists.

## Tests (`test/playcode_web/live/admin/play_notes_live_test.exs`)

Through `live/2`: the list (number, type, glossed word, where, context, text); each filter;
editing text, type, term and the word it follows, read back on the page and through
`PlayContent.list_notes/1`; an unlabelled type kept through an edit (also in the content
editor's form); delete; a stale or foreign id; the context bar's tab; Open in Content opening
the modal. `authorization_test.exs` gets the route's row.

## Out of scope

Adding notes here; changing several notes at once; moving a note to another line.
