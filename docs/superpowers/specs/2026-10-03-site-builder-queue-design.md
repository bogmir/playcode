# The site builder queues and batches

**Status:** design, 2026-10-03. Follows the static site follow-ups
(`docs/superpowers/specs/2026-10-02-static-site-followups-design.md`). That work made
`Playcode.Export.SiteBuilder` the one process that writes the admin's static site, and it
refuses a second job while one runs.

## Why

Measured on the 83-play dev corpus, an add or remove takes about 2–3 s. Most of that is
rewriting the whole search index: `Search.write_index/3` takes about 1.75 s. A play's
number in the index follows title order, so one insertion renumbers every other play. Its
vocabulary also touches most of the 447 shard files.

That cost grows with the corpus. At the 300 plays the project expects, an add takes an
estimated 7–8 s on this machine, and longer on the 1-vCPU Fly machine.

The admin page never waits, because jobs run in the background. But while a job runs, any
other switch gets "The site is busy…". So switching on twenty plays means twenty waits, and
twenty index rewrites.

## What changes

1. **Queue, don't refuse.** A request that arrives while a job runs is queued, and the
   caller is told so: each starter returns `:started` or `:queued`. A request identical
   to one already waiting is not queued twice.
2. **Batch adds and removes.** When a job ends, every add and remove at the front of the
   queue runs as one job, `{:batch, changes}`. A generate or a deploy runs on its own, in
   its turn. A batch takes the form values (version, base URL) of its latest request.
3. **One index write per batch.** A batch writes each play's pages, then the catalogue,
   then rewrites the search index once. Twenty switches cost twenty page writes and one
   index rewrite.
4. **Pages first.** Within a batch, the plays' pages and the catalogue are written before
   the index, and the builder broadcasts `{:site_builder, :published, job}` between the
   two. A play is in the preview after about a second, and its search follows a few
   seconds later.
5. **Only a play's last change in a batch counts.** A play added then removed in one
   batch is never written. A play removed then added is re-exported.
6. **Families once, with the final set.**
   - Every play a batch adds is written knowing which plays will be published when the
     batch ends, so a translation and its original added together link each other.
   - The published relatives of the plays it touched are re-exported once each, after
     the adds.
7. **Generate rebuilds the site as it is when it runs.** Today the admin page sends
   Generate the list of plays it shows when clicked. A Generate queued behind an add
   would rebuild without that play, and delete it from the site. The builder now works
   out the plays on disk when the generate starts (every complete play if the site is
   empty), and ignores a list it is given.
8. **A play that no longer exists is skipped.** A batch that adds a play archived or
   deleted since the click skips it, lands the rest, and reports it:
   `{:ok, %{skipped: [play_id]}}`. Any other crash fails the whole batch as today, and
   the queue carries on. A batch cut short leaves its plays' pages without their search
   entries. The next index write loads them, because the index's own list (`plays.js`)
   lacks them.
9. **Download is refused** while a job runs or requests wait. It reads the directory
   outside the builder.

## The admin page

- **Every switch shows where its play is going.** A play with a change queued or running
  is checked if it is being added and unchecked if it is being removed. Its switch is
  disabled with a spinner until the change's pages are published. Other switches stay
  usable.
- **Generate and Deploy queue.** Each is disabled only while its own job runs. A click
  while the builder is busy shows "Queued: it starts when the current build finishes."
- **Search catching up is visible.** Between `:published` and `:done`, "Updating search…"
  shows next to the preview link.
- **Flashes on done:**
  - one add: "Play exported to static site.";
  - one remove: "Removed %{code} from static site.";
  - more than one change: "%{count} changes applied to the static site.";
  - skipped plays: "A play that no longer exists was skipped." /
    "%{count} plays that no longer exist were skipped.".
- **Flashes on failure:**
  - a batch of one keeps "Could not add the play: …" and "Could not remove %{code}: …";
  - a larger batch shows "Could not apply %{count} changes to the site: %{reason}".

## Broadcasts

All on `"static_site"`:
- `{:site_builder, :queued, request}`: a request (`:generate`, `{:add, id}`, `{:remove, code}`
  or `:deploy`) is waiting.
- `{:site_builder, :started, job}`: `job` is `:generate`, `{:batch, changes}` or `:deploy`.
- `{:site_builder, :progress, job, info}`.
- `{:site_builder, :published, {:batch, changes}}`.
- `{:site_builder, :done, job, result}`.
- `{:site_builder, :failed, job, reason}`.

`SiteBuilder.status/0` returns `%{job: job | nil, queue: [request]}`.

## Out of scope

- A cap on batch size.
- Cancelling a queued request.
- Persisting the queue across a restart: the builder restarts empty, and the site on disk
  stays consistent.
- Keeping the decoded index in memory between jobs.
- Finer shards for the 300-play search download: a separate change, needed before about
  150 plays.

## Testing

TDD per CLAUDE.md, through the outermost API:
- `StaticSite.apply_changes/2` and the files it writes. Its `on_published` callback runs
  in the caller, so the state between pages and index can be read deterministically.
- `SiteBuilder`'s public functions and its broadcasts, read in arrival order.
- `ExportSiteLive` through `live/2`.

The timing arguments the follow-ups used hold here too: a build takes milliseconds, while
a second call follows within microseconds.
