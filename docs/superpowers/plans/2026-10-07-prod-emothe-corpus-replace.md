# Replace the EMOTHE Plays in Production Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Production (`playcode` on Fly, database `emothe` on `emothe-db-1g`) ends up with the same EMOTHE corpus as the local database on 2026-10-07: every EMOTHE play deleted and re-imported from the one-file-per-code folder `/home/bogdan/Downloads/emothe teis`, FileMaker data applied, every EMOTHE play complete, and the static site generated. The AL plays are not touched.

**Architecture:** Ship the importer changes first, then do everything else inside the running release: the TEI files and five small `.exs` scripts are uploaded to the site volume (`/data`, which survives a restart, unlike `/tmp`) and run with `bin/playcode rpc`. The import runs in a background process, so it survives the ssh session ending, logs its progress to `flyctl logs`, and skips codes already imported, so running it again resumes it. FileMaker goes through `/admin/filemaker` and the site through `/admin/export`, the paths that already exist for production. Copying the local database's rows across instead was rejected: the gazetteer's place ids differ between the two databases, and the TEI import is the path the code and tests support.

**Tech Stack:** flyctl v0.4.113 (`~/.fly/bin`, logged in), Elixir release `/app/bin/playcode`, Fly Postgres (`emothe-db-1g`, reached at `emothe-db-1g.flycast:5432`).

**Spec:** this conversation; the local run of 2026-10-07 is the reference result (371 EMOTHE plays incl. EMOTHE0277, 19 AL; `0 to change` from a FileMaker dry run; a full build of 371 plays at 465.2 MB).

## Global Constraints

- Only EMOTHE plays change. `like(code, "EMOTHE%")` is the selector everywhere; AL plays keep their rows, flags and links.
- Files imported: the folder's `EMOTHE*.xml`, minus `EMOTHE0708_LaSilvanire.xml` (cut off at verse 2677) and `EMOTHE0277_Zzzz_BracketsTest.xml` (a test file: "zzzz_brackets test", 0 verses). That is **370 files, one per code**. To publish 0277 after all, leave it in at Task 4 and expect 371 everywhere below.
- Nothing destructive runs before Task 3's backup exists on your disk.
- Deploying the site (pushing to `bogmir/emothe-static` and publishing on emothe.uv.es) is outward-facing and stays your call at Task 10.
- Commands are run from `/home/bogdan/Projects/playcode` with `export PATH="$HOME/.fly/bin:$PATH"`. The machine id `7847063c04e7e8` and volume id `vol_rkgqdp5ynq2mw0k4` were read on 2026-10-07; confirm them with `flyctl machine list -a playcode` and `flyctl volumes list -a playcode` if a step fails on them.

## Review Focus

- **The machine stops mid-import.** `fly.toml` has `auto_stop_machines = 'stop'` and `min_machines_running = 0`, and an ssh session is not traffic. Task 2 turns autostop off; if the machine restarts anyway (OOM), `/data` keeps the files and re-running `import` resumes.
- **The ssh session drops.** `import.exs` runs in an unlinked `Task` with its own group leader, and progress goes to `flyctl logs`, not to the session.
- **Production holds hand-made data the local database did not.** The wipe deletes hand-entered editors, sources, notes, play places and curated `form` values on EMOTHE plays, and every EMOTHE play that is not in the folder. Task 3's inventory prints all of these and is a stop point.
- **A stray file gets imported.** Task 4 asserts 370 files and zero repeated codes before anything is uploaded.
- **The database volume fills up.** `pg_data` is 1 GB; the new corpus is about 400 MB plus the import's WAL. Task 2, Step 3 extends it; during the import, `flyctl ssh console -a emothe-db-1g -C "df -h /data"` shows the margin.
- **The site does not fit.** 465 MB of site plus the deploy's `.git` copy did not fit the 1 GB volume; it was extended to 3 GB on 2026-10-07 (Task 2). Generate runs on 1 shared CPU and 1 GB of RAM; Task 9 has the memory contingency.

---

### Task 1: Ship the importer changes

The release must have migration `20261007120000` (note headings as `text`, for EMOTHE0113) and the paragraph, stanza and trailer import, or 7 plays fail or lose text.

- [x] **Step 1: Run the suite** — `609 tests, 0 failures (82 excluded)`. (`--include slow` has one failure that predates these changes, `import_live_test.exs:37`, a lock race with the corpus sweep; CI does not run it.)

- [x] **Step 2: Commit** — `118ecba fix some import gaps`; the migration came in an earlier commit. Both unpushed on 2026-10-07 (`main` ahead of `origin/main` by 5).

- [ ] **Step 3: Push and wait for the deploy**

Run: `git push origin main`, then `gh run watch` on the CI run and the `deploy-fly` run it triggers.
Expected: both green. `flyctl status -a playcode` shows a new image, machine `started`. The release command ran the migrations; Task 3's inventory prints the latest version to confirm.

### Task 2: Make the machine stay up, and give the site room

Do this after Task 1: a deploy resets the machine's settings from `fly.toml`.

- [ ] **Step 1: Turn autostop off**

Run: `flyctl machine update 7847063c04e7e8 --autostop=off -a playcode --yes`
Expected: the machine restarts and reports `started` in `flyctl status -a playcode`.

- [x] **Step 2: Extend the site volume to 3 GB** — done 2026-10-07, no restart needed

Ran: `flyctl volumes extend vol_rkgqdp5ynq2mw0k4 -s 3 -a playcode --yes`
Check: `flyctl ssh console -a playcode -C "df -h /data"` shows `3.0G  40M  2.8G`. A volume cannot shrink; 3 GB holds the site, the deploy's `.git` and the upload, at $0.15/GB per month ($0.45).

- [ ] **Step 3: Extend the database volume to 3 GB**

The database lives on `vol_40l3p92ozj187o94` (`pg_data`, **1 GB**). The full corpus measured 493 MB locally (`play_elements` 258 MB of rows plus 141 MB of indexes, 15% of it dead rows from re-imports), so a fresh import lands near 400 MB, next to whatever production holds now, while the bulk insert writes WAL up to Postgres's `max_wal_size` (1 GB by default) before a checkpoint recycles it. A full disk stops Postgres mid-import.

Run: `flyctl volumes extend vol_40l3p92ozj187o94 -s 3 -a emothe-db-1g --yes`
Then: `flyctl ssh console -a emothe-db-1g -C "df -h /data"`
Expected: about 2.9G available, at $0.30 a month more.

### Task 3: Back up the database

- [ ] **Step 1: Dump `emothe` on the database machine**

```bash
flyctl ssh console -a emothe-db-1g -C "su postgres -c 'pg_dump -Fc -d emothe -f /tmp/emothe-before-replace.dump'"
```

What worked on 2026-10-07, from an interactive `flyctl ssh console -a emothe-db-1g`: `PGPASSWORD="$SU_PASSWORD" pg_dump -h /var/run/postgresql -p 5433 -U postgres -Fc -d emothe -f /tmp/emothe-before-replace.dump` (Postgres listens on 5433 and asks the `postgres` role for its password, which the image keeps in `SU_PASSWORD`).

Expected: no output. **The command above failed on 2026-10-07:** `connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: No such file or directory`, so Postgres on this image is not on the default socket. Find it from an interactive `flyctl ssh console -a emothe-db-1g` (`ls -a /run/postgresql /var/run/postgresql /tmp | grep PGSQL`); Fly's Postgres image usually serves 5433 behind a proxy on 5432, which makes it `su postgres -c 'pg_dump -p 5433 -Fc -d emothe -f /tmp/emothe-before-replace.dump'`. If it fails with an authentication error instead, use the superuser password the Fly Postgres image keeps in its environment:

```bash
flyctl ssh console -a emothe-db-1g -C "sh -c 'PGPASSWORD=\$SU_PASSWORD pg_dump -h localhost -U postgres -Fc -d emothe -f /tmp/emothe-before-replace.dump'"
```

- [ ] **Step 2: Bring it home and check it**

```bash
mkdir -p ~/playcode-prod-replace
flyctl ssh sftp get /tmp/emothe-before-replace.dump ~/playcode-prod-replace/emothe-before-replace.dump -a emothe-db-1g
pg_restore -l ~/playcode-prod-replace/emothe-before-replace.dump | grep -c "TABLE DATA"
```

Expected: a non-empty file (4.96 MB on 2026-10-07). A local `pg_restore` older than 17 refuses it with `unsupported version (1.16) in file header`: Fly runs Postgres 17, whose archive format is 1.16. That is no problem for the rollback, which restores on the database machine; to count tables locally, `strings <dump> | grep -c "^TABLE DATA$"` gave 16, one per table.

- [ ] **Step 3: Snapshot the database volume as a second copy**

```bash
flyctl volumes snapshots create vol_40l3p92ozj187o94 -a emothe-db-1g
```

Expected: a snapshot id. Done 2026-10-07: `vs_904P0BAo6zZotQ7zPR8XNyj`, 62 MiB, **kept 5 days** (the volume's snapshot retention), so it is a safety net for the replacement itself, not an archive.

### Task 4: Stage the files and scripts

**Files (local, outside the repo):**
- Create: `~/playcode-prod-replace/replace/teis/*.xml`
- Create: `~/playcode-prod-replace/replace/run.sh`
- Create: `~/playcode-prod-replace/replace/scripts/{inventory,wipe,import,status,complete}.exs`

- [ ] **Step 1: Copy the TEI files and check them**

```bash
S=~/playcode-prod-replace/replace
mkdir -p $S/teis $S/scripts
cp "/home/bogdan/Downloads/emothe teis"/EMOTHE*.xml $S/teis/
rm $S/teis/EMOTHE0708_*.xml $S/teis/EMOTHE0277_*.xml
ls $S/teis | wc -l
ls $S/teis | sed 's/_.*//' | sort | uniq -d | wc -l
```

Expected: `370`, then `0`.

- [ ] **Step 2: Write `run.sh`**

```sh
#!/bin/sh
# Runs one of the scripts inside the live node: sh /data/replace/run.sh inventory
exec /app/bin/playcode rpc "Code.eval_file(\"/data/replace/scripts/$1.exs\")"
```

- [ ] **Step 3: Write `scripts/inventory.exs` (read-only)**

```elixir
# Read-only. What the wipe would destroy, and whether the release is current.
import Ecto.Query
alias Playcode.Repo
alias Playcode.Catalogue.{Play, PlayEditor, PlaySource, PlayEditorialNote}
alias Playcode.Places.PlayPlace
alias Playcode.Import.TeiCorpus

hand_entered = fn schema ->
  from(x in schema,
    join: p in Play,
    on: p.id == x.play_id,
    where: like(p.code, "EMOTHE%") and x.origin != "tei"
  )
  |> Repo.aggregate(:count)
end

plays =
  Repo.all(
    from p in Play,
      select: %{code: p.code, complete: p.is_complete, archived: not is_nil(p.deleted_at), form: p.form}
  )

{emothe, other} = Enum.split_with(plays, &String.starts_with?(&1.code, "EMOTHE"))
folder = TeiCorpus.collect_files(["/data/replace/teis"]) |> MapSet.new(&elem(&1, 0))

IO.puts("latest migration: #{Repo.one(from m in "schema_migrations", select: max(m.version))}")

IO.puts(
  "EMOTHE plays: #{length(emothe)} (complete #{Enum.count(emothe, & &1.complete)}, " <>
    "archived #{Enum.count(emothe, & &1.archived)}); other plays: #{length(other)}; folder: #{MapSet.size(folder)}"
)

IO.inspect(for(p <- emothe, TeiCorpus.base_code(p.code) not in folder, do: p.code),
  label: "EMOTHE in prod but not in the folder (deleted for good)",
  limit: :infinity
)

IO.inspect(for(p <- emothe, p.archived, do: p.code), label: "archived EMOTHE (come back unarchived)")
IO.inspect(for(p <- emothe, p.form, do: {p.code, p.form}), label: "curated form (lost)")

IO.inspect(
  %{
    editors: hand_entered.(PlayEditor),
    sources: hand_entered.(PlaySource),
    notes: hand_entered.(PlayEditorialNote),
    places: hand_entered.(PlayPlace)
  },
  label: "hand-entered rows on EMOTHE plays (lost)"
)
```

- [ ] **Step 4: Write `scripts/wipe.exs`**

```elixir
# Deletes every EMOTHE play except the two that exist only in production (Le favori
# and El favorito, in no TEI folder); its divisions, elements, characters, editors,
# sources, notes, places and statistics go with it (on_delete: :delete_all). AL plays stay.
import Ecto.Query

keep = ~w(EMOTHE0784_LeFavori EMOTHE0785_ElFavorito)

{n, _} =
  Playcode.Repo.delete_all(
    from p in Playcode.Catalogue.Play, where: like(p.code, "EMOTHE%") and p.code not in ^keep
  )

IO.puts("deleted #{n} EMOTHE plays, kept #{Enum.join(keep, ", ")}")
```

- [ ] **Step 5: Write `scripts/import.exs`**

```elixir
# Imports every TEI file under /data/replace/teis in a background process, so it
# survives the ssh session ending. Progress goes to `flyctl logs`. Codes already in
# the database are skipped, so running it again resumes an interrupted import.
Task.start(fn ->
  Process.group_leader(self(), Process.whereis(:user))
  require Logger
  alias Playcode.Import.TeiCorpus

  files = TeiCorpus.collect_files(["/data/replace/teis"])
  total = length(files)

  results =
    for {{code, _path} = file, i} <- Enum.with_index(files, 1) do
      [result] = TeiCorpus.import_all([file])
      Logger.info("replace-import #{i}/#{total} #{code} #{elem(result, 0)}")
      result
    end

  for {:error, code, reason} <- results,
      do: Logger.error("replace-import failed #{code}: #{inspect(reason, limit: 5)}")

  Logger.info("replace-import done #{inspect(Enum.frequencies_by(results, &elem(&1, 0)))}")
end)

IO.puts("import started; follow it with: flyctl logs -a playcode | grep replace-import")
```

- [ ] **Step 6: Write `scripts/status.exs` (read-only)**

```elixir
# Read-only. The corpus after the import.
import Ecto.Query
alias Playcode.Repo
alias Playcode.Catalogue.Play
alias Playcode.Import.TeiCorpus

codes = Repo.all(from p in Play, select: p.code)
emothe = Enum.filter(codes, &String.starts_with?(&1, "EMOTHE"))
folder = TeiCorpus.collect_files(["/data/replace/teis"]) |> MapSet.new(&elem(&1, 0))
imported = MapSet.new(emothe, &TeiCorpus.base_code/1)

IO.puts("EMOTHE plays: #{length(emothe)}; other plays: #{length(codes) - length(emothe)}")

IO.inspect(emothe |> Enum.frequencies_by(&TeiCorpus.base_code/1) |> Enum.filter(&(elem(&1, 1) > 1)),
  label: "codes imported twice"
)

IO.inspect(MapSet.difference(folder, imported) |> Enum.sort(), label: "in the folder, not imported")

IO.puts(
  "EMOTHE complete: #{Repo.aggregate(from(p in Play, where: like(p.code, "EMOTHE%") and p.is_complete), :count)}"
)
```

- [ ] **Step 7: Write `scripts/complete.exs`**

```elixir
# Marks every EMOTHE play complete, so Generate publishes it.
import Ecto.Query

{n, _} =
  Playcode.Repo.update_all(
    from(p in Playcode.Catalogue.Play,
      where: like(p.code, "EMOTHE%") and is_nil(p.deleted_at) and not p.is_complete
    ),
    set: [is_complete: true]
  )

IO.puts("marked complete: #{n}")
```

- [ ] **Step 8: Pack**

```bash
tar czf ~/playcode-prod-replace/replace.tgz -C ~/playcode-prod-replace replace
ls -lh ~/playcode-prod-replace/replace.tgz
```

Expected: one archive, tens of MB.

### Task 5: Upload and take the inventory

- [ ] **Step 1: Upload and unpack onto the volume**

```bash
flyctl ssh sftp put ~/playcode-prod-replace/replace.tgz /data/replace.tgz -a playcode
flyctl ssh console -a playcode -C "tar xzf /data/replace.tgz -C /data"
flyctl ssh console -a playcode -C "sh -c 'ls /data/replace/teis | wc -l'"
```

Expected: `370`.

- [ ] **Step 2: Run the inventory**

Run: `flyctl ssh console -a playcode -C "sh /data/replace/run.sh inventory"`
Expected: `latest migration: 20261007120000`, `folder: 370`, the AL count you know, and the lists of what the wipe destroys.

- [ ] **Step 3: Stop point — decide**

Go on only if every list is empty or you accept losing it: EMOTHE plays not in the folder, archived EMOTHE plays coming back, curated `form` values, hand-entered rows. The complete flags do not matter (Task 8 sets them all). If a hand-entered record matters, note it now from the admin pages, or stop here; nothing has changed yet.

### Task 6: Wipe and import

- [ ] **Step 1: Wipe**

Run: `flyctl ssh console -a playcode -C "sh /data/replace/run.sh wipe"`
Expected: `deleted 17 EMOTHE plays, kept EMOTHE0784_LeFavori, EMOTHE0785_ElFavorito` (2026-10-07: the inventory found 19 EMOTHE plays; you kept the two Madame de Villedieu plays, which are in no folder, and dropped the test plays EMOTHE0000_ObraDePrueba, EMOTHE0001 "Bart" and EMOTHE01787 "Fly").

- [ ] **Step 2: Start the import**

Run: `flyctl ssh console -a playcode -C "sh /data/replace/run.sh import"`
Expected: `import started; …`, and the command returns at once.

- [ ] **Step 3: Follow it**

Run: `flyctl logs -a playcode | grep replace-import`
Expected: `replace-import i/370 EMOTHE… ok` lines, ending with `replace-import done %{ok: 370}`. Locally the same import took 15 minutes on a fast machine with debug logging; on one shared CPU expect longer, and measure from the first lines. If the machine restarted, or the lines stopped without `done`, run Step 2 again: imported codes are skipped.

- [ ] **Step 4: Check the result**

Run: `flyctl ssh console -a playcode -C "sh /data/replace/run.sh status"`
Expected: `EMOTHE plays: 372` (370 imported plus 0784 and 0785), `other plays: 1`, `codes imported twice: []`, `in the folder, not imported: []`, `EMOTHE complete: 2`.

### Task 7: Apply the FileMaker data

- [ ] **Step 1: Preview**

Open https://playcode.fly.dev/admin/filemaker, upload `doc/w3emothe_T01_tituloEM.ndjson` from the repo (1.8 MB; the page takes up to 20 MB).
Expected: about 250 plays to change (locally, 248 on the first pass), **0 conflicting**, not in the index: production's AL plays plus 13 EMOTHE codes (0157, 0234, 0239, 0341, 0457, 0460, 0471, 0685, 0692, 0713, 0715, 0760, 0769), and EMOTHE0631's dating skipped (`"="`).

- [ ] **Step 2: Apply, then preview again**

Apply. Upload the same file again.
Expected: `0 to change`.

### Task 8: Mark every EMOTHE play complete

- [ ] **Step 1: Mark**

Run: `flyctl ssh console -a playcode -C "sh /data/replace/run.sh complete"`
Expected: `marked complete: 370`.

- [ ] **Step 2: Check**

Run: `flyctl ssh console -a playcode -C "sh /data/replace/run.sh status"`
Expected: `EMOTHE complete: 372`.

### Task 9: Generate the site

- [ ] **Step 1: Generate**

Open https://playcode.fly.dev/admin/export, press Generate, and keep the page open.
Expected: the play count above Preview reads 372, plus the AL play if it is complete; the size is about 465 MB.

- [ ] **Step 2: If the build dies**

Check: `flyctl logs -a playcode | grep -i "out of memory\|oom\|killed"`. If it ran out of memory, run `flyctl scale memory 2048 -a playcode`, wait for `started`, and press Generate again. It rebuilds only what is missing.

- [ ] **Step 3: Spot-check the preview**

Through Preview, open EMOTHE0329 (Gorboduc: five dumb shows with their text, five acts), EMOTHE0383 (Los amantes: four acts headed "Auto I"–"Auto IV") and EMOTHE0113 (Tartuffe: the long placet heading). Search for one word, *sueño*.

### Task 10: Deploy the site (your call), then clean up

- [ ] **Step 1: Check the publish server**

```bash
curl -s -X POST -H "X-Deploy-Token: $STATIC_SITE_PUBLISH_TOKEN" "https://emothe.uv.es/playcode-deploy.php?check=1"
```

Expected: PHP, zip, curl and write access OK, GitHub reachable. The download is about 465 MB unpacked, several times the 83-play site it has handled so far; if the check or the deploy times out, that server's PHP limits are the first suspect.

- [ ] **Step 2: Deploy**

Press Deploy on `/admin/export` and wait for the published address.

- [ ] **Step 3: Clean up**

```bash
flyctl ssh console -a playcode -C "rm -rf /data/replace /data/replace.tgz"
flyctl ssh console -a emothe-db-1g -C "rm /tmp/emothe-before-replace.dump"
flyctl machine update 7847063c04e7e8 --autostop=stop -a playcode --yes
```

Keep `~/playcode-prod-replace/emothe-before-replace.dump` until the new corpus has been in use for a while. If Task 9 scaled memory to 2 GB, decide whether to keep it (Generate needs it again) or `flyctl scale memory 1024 -a playcode`.

## Rollback

From any point after Task 3, this puts the database back as it was:

```bash
flyctl machine stop 7847063c04e7e8 -a playcode
flyctl ssh sftp put ~/playcode-prod-replace/emothe-before-replace.dump /tmp/emothe-before-replace.dump -a emothe-db-1g
flyctl ssh console -a emothe-db-1g -C "sh -c 'PGPASSWORD=\$SU_PASSWORD pg_restore -h /var/run/postgresql -p 5433 -U postgres --clean --if-exists -d emothe /tmp/emothe-before-replace.dump'"
flyctl machine start 7847063c04e7e8 -a playcode
```

The volume snapshot from Task 3, Step 3 is the fallback if the dump does not restore. The site on `/data/site` is only rebuilt by Generate, so until Task 9 it still matches the old database.
