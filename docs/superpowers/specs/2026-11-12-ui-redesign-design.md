# UI redesign: Playcode and the static site

Decided with the owner on 2026-11-12, after a review of the admin, the public LiveView pages
and the static site (screenshots at 1440 and 390 px, and the templates). The findings, one
line each, are in `docs/backlog.md`, *UI review (2026-11-12)*; this document is the design
they are built from. The mockup the owner approved is beside it:
`docs/superpowers/specs/2026-11-12-admin-design-mock.html` (open it in a browser; its numbers
are invented).

Each work package in *Work packages* is written to be handed to one agent by itself: it
names what to read, what to build, what is decided and what is the builder's.

## Why

- **The static site replaces `emothe.uv.es/biblioteca/`.** It will sit inside the EMOTHE
  portal, which stays. It must not look foreign beside it. The old biblioteca's design is
  poor and is not copied; the portal's colours are taken, the site's own layout and type kept.
- **The admin is what researchers work in every day**, and it has grown tab by tab: eleven
  tabs in one row, each page with its own width, icons without words, a play overview the
  owner calls horrendous.
- **One family.** The admin, Playcode's own reading pages and the static site should read as
  one product: the same violet, the same type, the same patterns.

## Goals, non-goals, anti-goals

Goals: the portal's palette on the static site and in Playcode; the admin rebuilt on the
mockup's shell and components; the play overview redone; the accessibility gaps the review
found closed; the static site in English and Spanish.

Non-goals: new features on any page beyond what is listed; the content editor's inner
workings (its tabs keep their behaviour); the ARTELOPE brand (the site is EMOTHE's);
changing what a page's data is or who may see it, with the one exception of the public-page
link.

Anti-goals, any of which makes the work a failure even if it looks good:

- A colour pair below 4.5:1 for text (3:1 for a graphic that carries meaning). Every pair
  below is measured; a new pair is measured before it is used.
- The static site needing a server, a third-party request or JavaScript to be read
  (`CLAUDE.md`, *Static site export*). The size budgets stay: `style.css` is at 23.4 KB of
  25 KB today, so the new header and the language switch must be written tightly.
- A page of the admin that `accessibility_test.exs` or `authorization_test.exs` no longer
  covers.
- A link to a public page that does not exist.

## The palette

Sampled from the portal's home page (a screenshot, not its stylesheet: the builder takes the
exact violet and gold from the portal's CSS if they differ by more than a shade).

### Light

| Token | Value | Use | Contrast |
|---|---|---|---|
| paper | `#f7f4ea` | page | |
| raised | `#fffdf7` | cards, inputs | |
| ink | `#221c2e` | text | 14.98 on paper |
| ink-2 | `#4a4458` | secondary text | 8.45 |
| muted | `#645d70` | labels, captions | 5.71 |
| faint | `#6f687b` | play codes, line numbers | 4.84 on paper, 5.24 on raised |
| hair | `#ddd6c2` | borders | |
| hair-2 | `#e9e4d3` | inner rules | |
| violet (accent) | `#4c2c82` | links, speakers, current item, primary buttons, the band | 9.59 on paper; white on it 10.55 |
| violet-2 | `#ece6f6` | current item's background | violet on it 8.65 |
| mark | `#efe6c4` | highlight | violet on it 8.44 |
| gold | `#d8c888` | on the violet band only | 6.3 on violet; 1.68 on white |
| nav on band | `#d9cfee` | the band's links at rest | 7.09 on violet |
| warn text / warn bg | `#7d5100` / `#fbf1d3` | the draft band | measure; `#8a5a00` gave 5.26 on the bg and 4.47 on the badge |

Gold is never text on a light page. Today's `--faint` (`#9aa3ae` on `#fbfbf9`) measures
2.46: that is S1, and the new value closes it.

### Dark

Proposed and measured, not yet seen on a screen: the builder looks at every page type in dark
before calling it done.

| Token | Value | Contrast on paper `#16131c` |
|---|---|---|
| raised | `#1d1925` | |
| ink | `#ebe7f0` | 15.05 |
| ink-2 | `#c4bdd0` | 10.08 |
| muted | `#a39cb0` | 6.94 |
| faint | `#8f889c` | 5.39 |
| accent | `#bfa9ee` | 8.85 (8.31 on raised) |
| mark | `#33284d` | accent on it 6.53 |
| band | `#3a2166`, white and gold on it | 13.21 and 7.89 |

Hairlines in dark: the builder's, in the same hue.

### The verse-form colours

`--f-romance`, `--f-redondilla`, `--f-quintilla`, `--f-other` on the new paper measure 5.32,
3.3, 2.99 and 2.11. They are not far from what they measure on today's paper. The builder
finds where each is used: as a graphic that carries meaning it needs 3:1, as text 4.5:1, and
the values move until they do, in both themes.

### Type

The static site's two families, Source Serif 4 and Inter, for everything. No third font: the
portal's condensed wordmark is answered with Inter 600, capitals, letter-spaced (the
reviewer's call). In Playcode: Inter for the interface, Source Serif for a play's title and
for reading text. Playcode serves the same font files the site ships
(`priv/static_site/fonts/`), from one place, not a copy (the reviewer's call; how they are
served is the builder's).

## The static site

Files: `priv/static_site/style.css`, `site.js`, `search.js`;
`lib/playcode/export/static_site/components.ex` (the shell, the top bar `.bar`, the
`.wordmark`, the rail) and `pages/*.heex`. Read `docs/static-site.md` first.

- **The header band.** Violet, a 3 px gold rule under it. The wordmark "EMOTHE" in white,
  "BIBLIOTECA DIGITAL" under it in gold, small. The site's own links (Catalogue, Search,
  About) in `nav on band`, the current one white with a gold underline.
- **S5, the portal's links.** In the band, apart from the site's own: Inicio
  (`https://emothe.uv.es/`), Base de datos (`https://emothe.uv.es/basededatos/`), and Escena
  digital and Enlaces at the addresses the portal's own menu gives. They are absolute links
  to another site: the one place a page points outside itself, which the Endings principles
  allow for a parent site; the About page says so. On a phone they fold with the site's
  links; how is the builder's.
- **The page.** The light and dark tokens above replace the variables at the top of
  `style.css`. Nothing else of the layout changes.
- **S1.** Done by the new `faint`.
- **S2, a skip link.** The first focusable element of every page, to the main content,
  visible on focus.
- **S4, the catalogue's sort.** Styled as the filter input beside it; the filter row and the
  list share one width.
- **S6, one sentence under the catalogue's title**, from the portal: "Repertorio que incluye
  obras pertenecientes a cinco tradiciones básicas de la primera modernidad del teatro
  europeo (la italiana, la inglesa, la francesa, la portuguesa y la española), así como
  traducciones y adaptaciones", and its English.

**Cost of shipping it.** A change to `style.css` alone is copied by Generate and rebuilds no
play. The band's markup, the skip link, S5 and S6 change the pages' code, so the next
Generate rebuilds every play: about six minutes on the performance machine, hours on the
shared CPU (`docs/production-reimport.md`). So these go out together, in one release, not
one by one.

### S3, the site in English and Spanish

Decided: both languages, with a switch. The design below is the reviewer's proposal; the
three open points at its end are settled before it is built.

- **One set of pages, both languages in each.** Not a tree per language: the site is 538 MB
  for 373 plays, the play text is the same in both, and a second tree doubles the size, the
  build and the push. Every interface string is printed twice,
  `<span lang="es">…</span><span lang="en">…</span>`, and `html[data-ui]` hides the other
  with one CSS rule. The interface is a few dozen short strings a page, so the cost is a
  kilobyte or two a page.
- **Without JavaScript the page reads in Spanish**: `<html lang="es" data-ui="es">` is what
  is written, as the old biblioteca was in Spanish (the reviewer's call). The switch (ES /
  EN, in the band) is `site.js`: it sets `data-ui` and `lang`, and keeps the choice where the
  site keeps its other settings; a line in the `<head>` applies it before the first paint.
- **Attributes** (an `aria-label`, a placeholder) cannot hold two languages: they are written
  in Spanish with the English in a `data-en`, and `site.js` swaps them. `<title>` stays the
  play's own title and "EMOTHE".
- **The play's text keeps its own `lang`**, as today (`lang={@edition.play.language}`).
- **Vocabularies** (the ones `PlayLabels` holds: form, kind, historical time and the rest)
  are translated both ways. **Free text a researcher wrote** (a dating note, a performance's note) is in
  whatever language they wrote it: printed once, as it is.
- **Search**: the normaliser does not change; the search page's strings and `search.js`'s
  messages follow the same rule.
- **Change tracking.** `StaticSite.Fingerprint` hashes the English translations only, and
  leaves `PlaycodeWeb.Gettext`'s code out because every Spanish edit of the admin's strings
  would otherwise rebuild the site. With Spanish on the site the Spanish translations must
  be tracked without bringing that back: the site's strings move to a gettext domain of
  their own, and the fingerprint hashes that domain's two files. `PlayLabels` is shared with
  the app, so its strings need the same treatment or a domain of theirs.

Open, to settle before building:

1. Spanish as the page's written default: the owner confirms.
2. The gettext domain: a short spike shows how many calls move and whether `PlayLabels`
   splits cleanly.
3. Whether a researcher's free text should carry a `lang`: only if there is a rule for the
   language notes are written in. A question for the team, in
   `docs/stakeholder/preguntas.html`.

## Playcode: the admin

Files: `assets/css/app.css` (the two daisyUI themes),
`lib/playcode_web/components/layouts.ex` and `layouts/admin.html.heex` (the shell, the
sidebar, `play_context_bar/1`), `core_components.ex`, and each LiveView under
`lib/playcode_web/live/admin/`.

### The themes

Both daisyUI themes take the palette: `base-100` raised, `base-200` paper, `base-300` hair,
`base-content` ink, `primary` the violet with white on it (in dark, the dark accent with a
dark text on it, measured). The semantic colours (info, success, warning, error) keep their
hues and are measured again on the new backgrounds. The comment in `app.css` that says the
colours are tuned to 4.5:1 stays true and says what they were tuned against.

### The shell

- **The top band**: violet with the gold rule, "PLAYCODE" and "ADMINISTRACIÓN", the language
  and theme switches and the user menu on it.
- **On a play's pages the sidebar holds the play's sections**, replacing the context bar's
  row of tabs (C1): "← Todas las obras", then Resumen; **Ficha**: Metadatos, Editores,
  Fuentes; **Tradición**: Testimonios, Representaciones, Bibliografía, Lugares; **Texto**:
  Contenido, Notas; **Ver**: Comparación (only for a play with an original or derived
  plays, as today), Vista previa, Página pública (see below). Each section that is a list
  shows its count. The current one carries `aria-current="page"`.
- **Entries are filtered through `Authz.can?/3`**, exactly as the global sidebar's are, so
  the menu offers no page its reader is bounced from.
- **The counts** come from one read for the play, not one per section, and a tab that adds
  or removes a row shows the new count without a reload.
- **The sidebar still folds** with the header's control. It starts open, except on Contenido
  and Comparación, which need the width (the reviewer's call). Below `lg` it is a folded
  "Secciones" block above the page, as the site's "Contents & tools".
- **Everywhere else** the global sidebar stays as it is (Contenido / Sitio / Sistema), in
  the new colours.
- **The play's title is said once** (C2): in the sidebar's head or the page's, not both; a
  section's `h1` is the section's name ("Representaciones"), not "…: Abrir el ojo".
- **Two widths** (C3): forms `max-w-4xl`, lists and the editor `max-w-7xl`. The content
  editor and the comparison may use the full width.

### The components

The mockup's parts, each built once and used by every page:

- **Card**: a raised box with a head (title, an optional count, one action on the right).
- **Label and value list**: a `dl`, labels in one aligned column, muted; values in ink.
- **Count tile**: a number, what it counts, the whole tile a link; at zero it reads
  "añadir" and links where the thing is added.
- **State band**: a badge and one sentence saying what the state means, with the one button
  that changes it.
- **Download group**: "Descargar" and TEI, HTML, PDF, EPUB as words (D1). The public
  catalogue uses the same.
- **Buttons**: one primary button a page (violet), the rest outlined (D2). One icon per
  action across the admin: one for edit, one for delete, one for archive.

Where they live (a module of their own or `core_components.ex`) is the builder's.

### The play overview

`/admin/plays/:id`, `play_detail_live.ex`. As the mockup, top to bottom:

1. **Head**: the title (serif), under it author, code (monospace chip), language, form. To
   its right: the download group, "Validar TEI", and "Editar metadatos" as the page's
   primary button. The validation's result prints under the head, as today.
2. **State band**: for a draft, "Borrador" and "Solo la ve el equipo. No está en el sitio
   publicado.", with "Marcar como completa". For a complete play, that it is complete and
   whether the last deploy published it, with "Volver a borrador". An archived play says so.
3. **Tiles**: versos, the top divisions (by their own name: jornadas, actos), personajes,
   representaciones, bibliografía, notas, testimonios. Each links to its section.
4. **Left column**: the **Ficha** card (idioma, atribución, datación, tiempo histórico,
   publicación, editorial, and the original title, the EMOTHE id and the edition's title
   where the play has them), with the long texts (autoridad, patrocinador, financiador,
   disponibilidad, licencia) folded under "Proyecto, financiación y disponibilidad"; the
   **Estructura** card, one line per top division with its verses.
5. **Right column**: **Edición** (the editors and their roles), **Relación** (the original
   and the derived plays, where there are any: the mockup leaves it out, the page keeps it),
   **Revisiones**, a **statistics summary** whose "Ver todas" opens the statistics section, and
   last the **Word import**, dashed, saying in bold that it replaces the whole text, on
   drafts only.
6. **The full statistics** leave the overview (the owner, 2026-11-12, after it was built:
   they looked horrible there): a section of their own, *Estadísticas* under *Texto* in the
   play's sidebar, drawn as the static site draws them. The item is in `docs/backlog.md`,
   *UI review*; the mockup is `2026-11-12-statistics-mock.html` beside this file.

Decided with the mockup: the characters' list leaves the overview (a tile; the list is in
Contenido), and the public address leaves the Ficha (it is the sidebar's link).

### Vista previa and Página pública

Today the context bar's "Público" opens `/plays/:code`, Playcode's own page. Decided:

- **Two links.** "Vista previa" opens `/plays/:code`, always there for staff: it is the only
  way to read a draft as readers will. "Página pública" opens the play's page on the
  published site, and is there only for a play the last deploy published.
- **A setting for the site's public address**: `STATIC_SITE_PUBLIC_URL`, beside the other
  `STATIC_SITE_*` settings in `config/runtime.exs`, written up in `docs/static-site.md`.
  `STATIC_SITE_PUBLISH_URL` is the fetch hook, not this. Unset, no play has the link.
- **Each deploy records what it published**: after a deploy succeeds, `SiteBuilder` keeps a
  copy of that build's `build.json` (it lists every published play with its
  `content_version`) beside the site directory, not in it, so it is not itself published.
  The link reads that record. It also lets the state band say "published" or "published,
  changed since". Until the first recorded deploy no play has the link.
- The path goes through `StaticSite.safe_code!/1`, like every path built from a code.

### The play form (E)

`play_form_live.ex`, over 2000 px today. One style of section (the card), each with its
name; a row of links to the sections at the top; a save bar that stays at the bottom of the
window and says when there are unsaved changes; labels in ink, not lighter than the values;
the small icon beside some labels gets a visible word or a help line. No field is added,
removed or moved between sections without the owner.

### Accessibility (B) and the rest of consistency (D)

- **B1, the modal** (`core_components.ex`, `modal/1`): `role="dialog"`, `aria-modal`,
  `aria-labelledby`, focus kept inside and returned on close (`focus_wrap`), a named close
  button. `accessibility_test.exs` gains the check.
- **B2**: the play list shows the state as a word in its own column, not only a coloured
  border.
- **B3**: a skip link in both layouts; `prefers-reduced-motion` honoured.
- **B4**: no text under 12 px.
- **D3**: file inputs as a drop zone with its own label in the page's language; the button
  counts with `ngettext` and says nothing at zero.
- **`/demo/ui`**: deleted, with its controller, templates, layout and routes.

## Playcode: the public LiveView pages (F)

`/plays` and `/plays/:code` take the static site's type, palette and patterns: they are what
"Vista previa" opens, so they should look like what will be published.

- **F1**: on a phone the play page's "Índice" starts folded.
- **F2**: the catalogue gets the site's filters with counts (language, form, kind) and a
  count of the plays shown; a row stacks at 390 px.
- **F3**: the play's head in the site's type; the raw address is not printed.

Not copied: the site's markup. These pages keep their LiveView components.

## Work packages

In order. A was built and merged on 2026-11-12 (`156e4ec`). Package 1 was started the same day:
its builder reads what is already there before adding to it. Every package follows
`CLAUDE.md`: the failing test first, `mix precommit` green, a row in
`authorization_test.exs` for a new route, a path in `accessibility_test.exs` for a new page,
its item moved from `docs/backlog.md` to `docs/history.md` when done.

| # | Package | Reads | Depends on | Suggested model |
|---|---|---|---|---|
| 1 | Admin design: themes, shell, components | *The palette*, *Playcode: the admin* up to *The components*, the mockup | A | Opus |
| 2 | Play overview | *The play overview*, the mockup | 1 | Opus |
| 3 | Vista previa and Página pública | that section, `docs/static-site.md` | 1 | Opus |
| 4 | B and D's rest, `/demo/ui` | *Accessibility (B) and the rest of consistency (D)* | 1 | Sonnet |
| 5 | The play form | *The play form (E)* | 1 | Opus |
| 6 | The play's other tabs on the components | *The components* | 1 | Sonnet |
| 7 | Static site: palette, band, S1, S2, S4, S5, S6, one release | *The palette*, *The static site* | none | Sonnet; Opus for the dark theme and the verse-form colours |
| 8 | Public LiveView pages | *Playcode: the public LiveView pages (F)* | 1, 7 | Opus |
| 9 | S3 | *S3*, after its three open points are settled | 7 | a spike and a plan first, then Opus |

Package 7 touches nothing of the admin and can run beside any of 1 to 6. Package 2's state
band says whether a play is published only once package 3 is in; before that it says draft
or complete.

## Left to the builder

File and module layout of the components; how the fonts are served; the dark hairlines; how
the band's links fold on a phone; where the deploy record's file sits; the Spanish and
English wording of new strings, checked against `CONTEXT.md`'s glossary.

## The reviewer's calls, for the owner to overturn

1. No third font for the wordmark; Inter capitals instead.
2. Playcode serves the site's font files, and a play's title in the admin is in Source Serif.
3. The play's sidebar starts open, folded only on Contenido and Comparación.
4. ~~The full statistics stay on the overview~~: overturned by the owner on 2026-11-12, a
   section of their own (the overview, part 6).
5. The link to Playcode's own page is called "Vista previa", for a draft and a complete play
   alike.
6. The site's pages are written in Spanish, English by the switch (S3, open point 1).
7. The portal's links in the site's band are absolute links out of the archive.

## Not checked by the review

The dark theme on a screen; modals, drag-and-drop and live validation in use; the site's
statistics, search and comparison pages; the portal's exact colour values and the addresses
of Escena digital and Enlaces.
