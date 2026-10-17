# Re-importing the TEI corpus on production

How to re-import every play from its TEI file on Fly, the way it was done on 2026-10-07 and
2026-10-15. A re-import is how a change to what the importer reads (a new field, a kind kept,
line breaks) reaches the plays already in the database: the code alone changes nothing until
each play is read again. `mix playcode.import.tei --force` does it on dev; this is the
production version, with what went wrong each time.

A forced re-import replaces, for each play, its text (divisions, elements, notes, characters)
and every row that came from its file (`origin: "tei"`: editors, sources, paratexts,
witnesses, place links). Hand-entered rows (`origin: "manual"`), FileMaker rows and the
curated columns (`@platform_owned` in `TeiImport`) are kept. Each play is one transaction:
an interrupted run leaves every play either wholly old or wholly new.

## The machines

| What | Fly app | Machine | Size day to day |
|---|---|---|---|
| The application | `playcode` | `7847063c04e7e8` | shared-cpu-1x, 1 GB (`fly.toml`) |
| The database | `emothe-db-1g` | `d8d14e7b0465d8`, volume `vol_40l3p92ozj187o94` | shared-cpu-1x, 512 MB |

`flyctl` lives at `~/.fly/bin/flyctl`; it is not on the PATH of Claude Code's `!` shell.
In this directory `fly.toml` makes `playcode` the default app, so every command for the
database names it with `-a emothe-db-1g`.

**Push nothing to `main` while a run or a site build is going.** A green CI deploys, and a
deploy restarts `playcode` with `fly.toml`'s size and autostop, which ends the run. On
2026-10-15 a docs-only push during Generate was caught by cancelling its CI run
(`gh run cancel <id>`; the deploy then skips); rerun it afterwards (`gh run rerun <id>`),
which also puts `playcode` back to its usual size.

## The run

Four commands do the mechanical steps, run from this directory with flyctl; the three
decisions, after the dry run, after the counts and after the preview, stay with a person.

```bash
mix playcode.fly.reimport prepare     # steps 2-5 below, then stops
mix playcode.fly.reimport run         # steps 6 and 7; the machines stay up
mix playcode.fly.reimport generate    # scales up, step 10's Generate, then step 9
mix playcode.fly.reimport deploy      # step 10's Deploy, after the preview
mix playcode.fly.reimport scale-down  # step 9 alone, after an aborted run or build
```

1. **Deploy the code** (step 1 below).
2. **`prepare`** snapshots the database volume and waits for the snapshot, starts the app
   if the proxy stopped it for want of traffic (on 2026-10-17 the upload found no VM), uploads
   `doc/tei_corpus/` (`--dir` for another folder) and checks the count on the machine,
   scales both machines up with autostop off, and runs the dry run, printing each play as
   it is read. It ends by listing the lines that need a look (hand fixes the re-import
   would lose, an archived play it restores, a file it cannot read) or saying there are
   none. Step 5 says what to do with them. Running `prepare` again is safe.
3. **`run`** re-imports every play not imported since its file was uploaded
   (`resume: true`). When a run stops part way it shows the machine's status, starts it,
   and runs again, three times at most. When a play fails it stops: fix the cause
   and `run` again, which re-imports only what is left. Either way the machines stay
   scaled up, for the build.
4. **Check** what the change was for (step 8).
5. **`generate`** is Generate on `/admin/export`, run over SSH on performance-1x with
   autostop off: it scales both machines up as `prepare` does, leaving one already there
   (after `run`) as it is, since a resize restarts it. It waits for the build's end,
   printing its progress. When the session drops before it, it asks again: the build goes
   on in the app, and the second Generate waits behind it. When the build is done it
   scales both machines back and turns autostop on; when it fails they stay up. It also
   stands alone: after a deploy that changed the site's code every play is rebuilt, six
   minutes on performance-1x and over two hours on the shared CPU (2026-10-17), so run
   `generate`, not the export page's button.
6. **Check the preview** on `/admin/export`, then **`deploy`**: Deploy, over SSH, with
   autostop off while it pushes and back on after it.

The machines' ids are constants in `lib/mix/tasks/playcode.fly.reimport.ex`; a new
machine or volume means editing them there and in the table above.

## By hand

What the commands do, for when one of them fails part way, or something new is needed.

1. **Deploy the code.** Push `main`; CI, then `.github/workflows/deploy-fly.yml`, deploys
   and runs the migrations. Wait for both runs to pass (`gh run list --limit 3`).

2. **Snapshot the database volume.** The re-import cannot be undone any other way.

   ```bash
   ~/.fly/bin/flyctl volumes snapshots create vol_40l3p92ozj187o94 -a emothe-db-1g
   ~/.fly/bin/flyctl volumes snapshots list vol_40l3p92ozj187o94 -a emothe-db-1g   # wait for "created"
   ```

3. **Put the files on the machine.** `doc/tei_corpus/` (git-ignored) holds the production
   corpus, 372 files on 2026-10-15, EMOTHE0784 and 0785 among them. One play per code; the
   importer reads every `*.xml` in the folder it is given, not its subfolders.

   ```bash
   rm -rf /tmp/tei && mkdir /tmp/tei && cp doc/tei_corpus/*.xml /tmp/tei/
   tar czf /tmp/tei.tgz -C /tmp/tei .
   ~/.fly/bin/flyctl ssh sftp put /tmp/tei.tgz /data/tei.tgz -a playcode
   ~/.fly/bin/flyctl ssh console -a playcode -C "sh -c 'rm -rf /data/tei && mkdir /data/tei && tar xzmf /data/tei.tgz -C /data/tei && ls /data/tei | wc -l'"
   ```

4. **Scale both machines up, and turn autostop off.** On shared CPUs a run of this size uses
   up the burst allowance within minutes; then Fly lends the machine almost no CPU (89.7%
   steal on 2026-10-15) and imports hit the 60-second database timeout (half the plays on
   2026-10-07). Autostop: the proxy stops `playcode` when it sees no web traffic, and an SSH
   session is not traffic, so it stopped the machine ten minutes into the run on 2026-10-15.

   ```bash
   ~/.fly/bin/flyctl machine update d8d14e7b0465d8 --vm-size performance-1x -a emothe-db-1g --yes
   ~/.fly/bin/flyctl scale vm performance-1x -a playcode
   ~/.fly/bin/flyctl machine update 7847063c04e7e8 --autostop=off -a playcode --yes
   ```

   Do this before the dry run: restarting the database ends any run in progress (the dry run
   lost its connection on 2026-10-15). `machine update` needs `--yes` outside a terminal;
   `scale vm` has no `--yes` and does not ask.

5. **Dry run.** It writes nothing; it prints one line per play as it reads its file (about a
   minute for all of them scaled up, an hour throttled), then a summary.

   ```bash
   ~/.fly/bin/flyctl ssh console -a playcode -C "bin/playcode rpc 'Playcode.Release.import_tei(\"/data/tei\", dry_run: true, force: true)'" > /tmp/dry.log
   grep -E "edited since their import|undoes|keeps|restores it" /tmp/dry.log
   tail -1 /tmp/dry.log
   ```

   Stop here if any line says a play has rows `edited since their import` (file rows changed
   in Playcode, which the re-import replaces) or `undoes N hand edit(s)` (logged edits to the
   text): those are hand fixes that would be lost. Look at each with the project first.
   `keeps N hand-entered record(s)` is fine; `restores it from the archive` un-archives a play.
   A note on dev: a backfill script's `update_all` also counts as edited (152 sources and 13
   characters on 2026-10-15); production had none.

6. **The run.** About 5 plays a minute on performance-1x, so a little over an hour for 372.

   ```bash
   ~/.fly/bin/flyctl ssh console -a playcode -C "bin/playcode rpc 'Playcode.Release.import_tei(\"/data/tei\", force: true)'" > /tmp/run.log
   tail -3 /tmp/run.log    # "imported N, skipped 0, failed 0"
   ```

   Progress: `grep -c "Importing TEI file" /tmp/run.log`. A failure prints the play's code
   and the error as it happens.

7. **If it stops part way**, run step 6 again with `resume: true` as well: it skips every
   play imported since its file was uploaded, so it carries on where the last run stopped.
   The upload dates each file (`tar -m`), and a new upload starts over.

   ```bash
   ~/.fly/bin/flyctl ssh console -a playcode -C "bin/playcode rpc 'Playcode.Release.import_tei(\"/data/tei\", force: true, resume: true)'" > /tmp/run.log
   ```

   Check the machine's events first
   (`~/.fly/bin/flyctl machine status 7847063c04e7e8 -a playcode`): `requested_stop=true` is
   autostop, `oom_killed=true` memory. On 2026-10-15, before `resume`, the files left to
   do were copied into `/data/tei-rest` by hand.

8. **Check.** What the change was for, counted on production, for example:

   ```bash
   ~/.fly/bin/flyctl ssh console -a playcode -C "bin/playcode rpc 'import Ecto.Query; IO.inspect(Playcode.Repo.aggregate(from(x in Playcode.Catalogue.Paratext, where: x.kind == \"nota\"), :count))'"
   ```

9. **Scale back, autostop back on.**

   ```bash
   ~/.fly/bin/flyctl machine update 7847063c04e7e8 --autostop=stop -a playcode --yes
   ~/.fly/bin/flyctl scale vm shared-cpu-1x --vm-memory 1024 -a playcode
   ~/.fly/bin/flyctl machine update d8d14e7b0465d8 --vm-size shared-cpu-1x --vm-memory 512 -a emothe-db-1g --yes
   ```

   The next deploy puts `playcode` back to `fly.toml`'s size and autostop anyway, but not the
   database.

10. **Generate the site** from `/admin/export`. A re-import moves every play's
    `content_version`, and a change to a fingerprinted module (`StaticSite.Fingerprint`)
    marks the whole site changed, so Generate rebuilds every play *on the site*
    (`SiteBuilder.codes_in_site/0`): a complete play not yet on it is added from the export
    page, not by Generate ("Add every complete play" adds them all in one batch). On 2026-10-15 that was 212 of the 373 complete plays, about four
    minutes on performance-1x, 560 MB of memory. Then Deploy, after checking the preview.

    `generate` and `deploy` do both over SSH (`Playcode.Release.generate_site/0` and
    `deploy_site/0`, which wait for the builder's job and print its end). By hand, from the
    export page, keep the page open: its connection is the web traffic that keeps autostop
    away. A build started over `bin/playcode rpc` with autostop on sends no traffic, and the
    proxy stops the app in the middle of it (2026-10-16, ten minutes into a four-play
    Generate); the commands turn autostop off first. Deploy only pushes what Generate built:
    on 2026-10-17 a Deploy pressed before Generate sent the build of the day before again.

## Why it is not all one command

Each decision above is one someone should see: the snapshot exists, the dry run shows no
hand fixes, the counts match, the preview is right. `prepare` stops before the first; the
counts come after `run`, the preview after `generate`, and only `deploy` publishes.
