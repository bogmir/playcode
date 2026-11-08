# The play form's two switches: Completa and Mostrar las variantes

A small fix, written 2026-11-09 as a handoff for its own session. The owner asked what the two
checkboxes under *Numeración* in the play form (`/admin/plays/:id/edit`) mean, and whether
every play needs them.

## What the switches are

Both are curated columns on `plays`, kept out of the TEI file on purpose (see `CLAUDE.md`,
*The TEI file is a complete copy of a play*).

- **`is_complete` ("Completa"):** whether the play is published.
  - On: visitors see it at `/plays/:code` and through `/api/v1`, and it goes into the static
    site (`export_site_live.ex:667`).
  - Off: it is a draft, seen by staff only; visitors get a 404.
  - A play imported from a file always arrives as a draft (decided 2026-10-13). Every play
    has the switch.
- **`show_variants` ("Mostrar las variantes textuales"):** whether readers see the play's
  variant readings (`Note.variant?/1`, notes of type `"variante"`). It is on by default
  (2026-10-18). Hamlet's is kept off in production until its editor finishes (question 2,
  backlog).

**Only 7 plays have variants** (dev, 2026-11-09):

| Play | Variants |
|---|---|
| 0551 | 309 |
| 0560 | 189 |
| 0460 | 127 |
| 0010 (Hamlet) | 90 |
| 0187 | 64 |
| 0530 | 62 |
| 0435 | 10 |

For the other 400 plays the box is ticked and does nothing. (Notes with an empty `readings`
array are not variants; don't count them.)

## Changes

### 1. The variants box only where there are variants (decided by the owner)

- The play form shows "Mostrar las variantes textuales" only when the play has at least one
  variant.
- Under the box goes a hint line in the same style as the team note's
  (`mt-1 text-xs text-base-content/70`), with the count, for example "Muestra al lector las 90
  variantes de la obra; el archivo TEI las conserva siempre."
- Count with one query on `play_notes` (`type = Note.variant()`). Add a `PlayContent`
  function, or reuse one if it exists.
- A new play (`live_action == :new`) has no variants, so it shows no box. Its default
  (`true`) stays.
- When the box is hidden, its value must not be sent as false. A hidden input or a leftover
  default could switch a play's variants off, so check what the form submits.
- Test through the LiveView (`play_form_live_test.exs`):
  - a play without variants has no such checkbox;
  - a play with variants shows the box with its count;
  - the existing test "Show variant readings off hides the variants from readers, never from
    the file" (line ~405) still passes; give its play a variant if it has none.
- Prove each new test bites (`bin/bites`).

### 2. Completa: one control, not two (decided by the owner, 2026-11-09)

The same switch is set in two places:
- the form's checkbox (`play_form_live.ex:777`);
- the play page's *Estado* toggle, Borrador / Completa (`play_detail_live.ex:103`,
  `set_status`, `aria-pressed`). The play list also shows the status.

**The UI principle:** one setting should have one place to change it. Two controls make
readers wonder which one is the real switch. A form opened before a toggle and saved after it
also writes back the stale value.

A shortcut beside a full editor is justified only when the shortcut is the quick path to
something the editor shows in full. Here the toggle is already the clear, prominent control,
and publishing is a status, not metadata.

**Decided:**
- Remove the checkbox from the form.
- Keep the *Estado* toggle on the play page.
- A new play is created as a draft (the column's default) and published from its page.
- Check that the form's save no longer touches `is_complete`: no field means no param, so
  `update_play_from_form/2` leaves it alone. Check `cast` too.

**Tests:**
- the form has no "Complete" checkbox;
- saving the form keeps `is_complete` as it was, whether true or false;
- the detail toggle's existing tests (`play_detail_live_test.exs`) still pass.

Remove the gettext strings that are no longer used (`mix gettext.extract --merge`, and check
the fuzzy entries).

## Records

- `docs/history.md` when done.
- `docs/stakeholder/ida-y-vuelta.html` only if its admin column names the form's checkbox for
  either row.
- The accessibility test (`accessibility_test.exs`) already renders the form; run it.

## Suggested skills

- `superpowers:test-driven-development`;
- `superpowers:verification-before-completion`;
- `superpowers:finishing-a-development-branch` (merge locally; no PR; push only when told).
