defmodule Playcode.Import.Performances do
  @moduledoc """
  The one-time move of FileMaker's historical performances into Playcode (S5). Spec: "The
  import" in docs/superpowers/specs/2026-10-19-s5-performances-design.md.

  `load/1` reads `T11` (the performances, their cast, actors, roles and companies), `T13`
  (the sources and the city and publisher tables behind them) and `T10`, whose rows naming a
  performance are places of action. `plan/2` decides what to write: it reads the database
  but never writes. `report/1` prints the plan.

  A performance becomes one planned performance for each play holding its version, and a
  play already imported (a `filemaker` performance, or the "import" row in the activity log,
  which outlives them) is skipped whole, so a curator's deletions stick. A performance that
  says nothing, which `Performance.changeset/2` would refuse, is left out and reported.

  A source record is read as S4 reads a `T12.1` one (`Import.Bibliography.record_attrs/2`).
  FileMaker made a record for nearly every volume and page cited, so the records of one work
  are listed by hand (`@works`): the work is one entry, and each performance keeps the
  volume and pages of its own record. Every other record is a work of its own.

  Nothing FileMaker wrote in `{…}` is copied: `{Falta año pub}` fills the composed citation
  where a field is blank, and a field holding only that is blank.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Bibliography
  alias Playcode.Bibliography.Entry
  alias Playcode.Catalogue.Play
  alias Playcode.Import.Bibliography, as: ImportBibliography
  alias Playcode.Import.{FilemakerXml, Places}
  alias Playcode.Performances
  alias Playcode.Performances.{Actor, Performance}
  alias Playcode.Repo
  alias Playcode.Text

  @default_dir "doc/ctce_dades"

  # T13's types are T12.11's, same ids (`Import.Bibliography`), so T13.3 is not read.
  @files [
    performances: "T11_ObraRepresentacion.xml",
    cast: "T11.1_ActorRepresentacion.xml",
    actors: "T11.11_ActorNombre.xml",
    roles: "T11.22_ActorRol.xml",
    companies: "T11.3_CompaniaNombre.xml",
    sources: "T13_FuenteInformacion.xml",
    cities: "T13.1_Ciudad.xml",
    publishers: "T13.2_Editorial.xml"
  ]

  @sexes_file "T11.12_ActorSexo.tab"

  # T11.12 by its Spanish word; "desconocido" is no sex.
  @sexes %{"hombre" => "man", "mujer" => "woman"}

  # T11.2's ids 1-8 are `Performance.venue_types/0`, in order.
  @venue_types Performance.venue_types()
               |> Enum.with_index(1)
               |> Map.new(fn {type, id} -> {Integer.to_string(id), type} end)

  # T13 records of one work, by work; the work's entry as the project cites it (owner's
  # decisions, 2026-10-19). Wiggins's and Mora Sena's are every record a performance cites;
  # CATCOM's two come with its licence, which requires printing it with the citation.
  @works %{
    wiggins: %{
      records:
        ~w(87 88 89 90 93 94 95 189 190 191 192 193 195 196 197 207 208 228 229 230 231 232 260 269 302 303 311 312 314 315 316 317 318 319 320 325 326 327 328 332 337 338 339 340 341 374 375 376 382 383 389 391 392 393 394 395 396 397 406 407 408 415 416 417 418 419 420 421 424 425 426 427 428 429 430 431 432 433 434 435 457),
      kind: "catalogue",
      attrs: %{
        pub_type: "book",
        monogr_author: "Wiggins, Martin, in association with Catherine Richardson",
        monogr_title: "British Drama 1533–1642: A Catalogue",
        pub_place: "Oxford",
        publisher: "Oxford University Press",
        year_text: "2012–"
      }
    },
    catcom: %{
      records: ~w(119 468),
      kind: "catalogue",
      attrs: %{
        pub_type: "electronic",
        monogr_author: "Ferrer Valls, Teresa et al.",
        monogr_title:
          "Base de datos de comedias mencionadas en la documentación teatral (1540-1700). CATCOM",
        year_text: "2012–",
        url: "http://catcom.uv.es",
        public_note:
          "Copyright © DICAT Grupo de investigación teatral bajo Licencia Creative Commons BY-NC-ND."
      }
    },
    restoration_comedy_1671: %{
      records: ~w(284 285 286 287 288 289 290),
      kind: "catalogue",
      attrs: %{
        pub_type: "book",
        monogr_author: "Mora Sena, María José; Prieto Pablos, Juan Antonio",
        monogr_title: "Restoration Comedy, 1671–1682: A Catalogue",
        pub_place: "New York",
        publisher: "Teneo Press",
        year_text: "2018"
      }
    }
  }

  @work_of for {work, %{records: records}} <- @works, id <- records, into: %{}, do: {id, work}

  # Lone records that are catalogues, not criticism: Harbage's Annals, Gómez-Lara's
  # Restoration Comedy 1660-1670, the London Stage Database.
  @catalogues ~w(35 102 481)

  # Records that are an edition S4 brought in, with the entry's `filemaker_id`: a second
  # entry would cite one edition twice on a page. Gibson's Massinger, Brome Online, Dryden.
  @existing %{"97" => "T04:116", "98" => "T04:385", "81" => "T04:418"}

  # A record with no author or title, which an entry cannot be: the hand list names it.
  @named %{"479" => %{monogr_title: "data.bnf.fr", kind: "catalogue"}}

  # FileMaker's note is no note for researchers in two records: Arden Early Modern Drama is a
  # series, and Brome's address a URL.
  @notes %{
    "96" => %{series: "Arden Early Modern Drama", note: nil},
    "98" => %{url: "https://www.dhi.ac.uk/brome/", note: nil}
  }

  # EMOTHE0313's 1700 performance has no cast in FileMaker: the play's cast list is its cast.
  @cast_list_performance "145"

  @roman %{?I => 1, ?V => 5, ?X => 10, ?L => 50, ?C => 100}

  def default_dir, do: @default_dir

  @doc "Reads the tables from `dir`: `T11` and `T13`'s, the sexes' `.tab` file, and `T10`."
  def load(dir) do
    with {:ok, data} <- FilemakerXml.read_tables(dir, @files),
         {:ok, sexes} <- read_sexes(Path.join(dir, @sexes_file)),
         {:ok, places} <- Places.load(dir) do
      {:ok, data |> Map.put(:sexes, sexes) |> Map.put(:places, places)}
    end
  end

  # Tab-separated lines ended by CR, "1\thombre": `%{"1" => "hombre"}`.
  defp read_sexes(path) do
    case File.read(path) do
      {:ok, text} ->
        lines = String.split(text, ["\r", "\n"], trim: true)
        {:ok, Map.new(lines, fn line -> line |> String.split("\t") |> List.to_tuple() end)}

      {:error, reason} ->
        {:error, {Path.basename(path), reason}}
    end
  end

  @doc """
  What the import would write. Reads the database, writes nothing. See the moduledoc.

  `performances` are the planned performances in FileMaker's order, each:

    * `play_id`, `code`, `ref` (`"T11:<id>"`) and `attrs`, the performance's own fields
      (`date_text`, `venue`, `venue_type`, `note`);
    * `company`, a name or nil; `cast`, `%{actor: attrs, role: role}` in order, the actor's
      `surname`, `forename`, `nickname` and `sex`;
    * `place` and `state`, keys into `places`; `source`, a key into `works`, with its own
      `source_volume` and `source_pages`; and `cast_from_cast_list`.

  `places` and their report lines (`merged`, `twinless`, `no_country`, `reused`) are
  `Import.Places.place_plan/2`'s. `works` holds one entry per work cited: its `attrs`, the
  entry it is `existing` (a `filemaker_id`, when Playcode has it), the entry it is
  `identical` to (an id, when Playcode has an entry with its description), its `records`
  (ids, in order) and the `ref` it is created with. `companies` and `actors` are the ones
  the performances name, `reused_*` those Playcode already has, `merged_*` those FileMaker
  has under two records. `skipped` holds labels, by reason: `empty`, `undated` (kept, with no
  year to order by), `cast`, `source` and `place`. `not_held` counts the performances on
  versions we do not hold, and `already_imported` names the plays skipped whole.
  """
  def plan(data, plays) do
    imported = imported_play_ids()
    by_code = Enum.group_by(plays, &Play.short_code(&1.code))
    companies = lookup_companies(data)
    actors = lookup_actors(data)

    owned =
      for row <- sorted(data.performances, "_kp_IdObraRepresentacion") do
        {row, Map.get(by_code, FilemakerXml.version_code(row["_k_IdObraTitulo"]), [])}
      end

    pending =
      for {row, plays} <- owned,
          plays = Enum.reject(plays, &MapSet.member?(imported, &1.id)),
          plays != [],
          do: {row, plays}

    {described, empty} =
      Enum.split_with(pending, fn {row, _plays} -> described?(row, companies.names) end)

    {placed, places} = lookup_places(data, described)
    sources = lookup_sources(data, described)
    cast = lookup_cast(data, described, actors.by_id)

    performances =
      for {row, plays} <- described, play <- plays do
        id = row["_kp_IdObraRepresentacion"]
        {place, state} = Map.get(places, id, {nil, nil})
        {source, volume, pages} = Map.get(sources.by_performance, id, {nil, nil, nil})

        %{
          play_id: play.id,
          code: play.code,
          ref: "T11:" <> id,
          attrs: attrs(row),
          company: companies.names[value(row, "_k_IdCompaniaNombre")],
          cast: Map.get(cast.by_performance, id, []),
          place: place,
          state: state,
          source: source,
          source_volume: volume,
          source_pages: pages,
          cast_from_cast_list: id == @cast_list_performance
        }
      end

    already_imported =
      for {_row, plays} <- owned,
          play <- plays,
          MapSet.member?(imported, play.id),
          uniq: true,
          do: play.code

    used_companies = MapSet.new(described, fn {row, _plays} -> company_id(row) end)
    names = performances |> Enum.map(& &1.company) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    people = performances |> Enum.flat_map(& &1.cast) |> Enum.map(& &1.actor) |> Enum.uniq()

    Map.merge(placed, %{
      performances: performances,
      works: sources.works,
      companies: names,
      reused_companies: reused_companies(names),
      merged_companies: merged(companies.twins, used_companies),
      actors: people,
      reused_actors: reused_actors(people),
      merged_actors: merged(actors.twins, cast.used),
      skipped: %{
        empty: for({row, [play | _]} <- empty, do: label(play, row)),
        undated: undated(described),
        cast: cast.skipped,
        source: sources.skipped,
        place: placed.skipped |> Map.values() |> List.flatten()
      },
      not_held: Enum.count(owned, &match?({_row, []}, &1)),
      already_imported: Enum.sort(already_imported)
    })
  end

  # --- what a performance says

  defp attrs(row) do
    %{
      "date_text" => value(row, "ObrRep_Fecha"),
      "venue" => row |> value("ObrRep_NombreCircunstancia") |> first_line(),
      "venue_type" => @venue_types[value(row, "_k_IdCirEscenica")],
      "note" => value(row, "ObrRep_Nota")
    }
  end

  # EMOTHE0379's venue is followed by CATCOM's credit line, which prints with its citation.
  defp first_line(nil), do: nil
  defp first_line(text), do: text |> String.split("\n", parts: 2) |> hd()

  # The fields `Performance.changeset/2` wants one of (`validate_described`).
  defp described?(row, companies) do
    attrs = attrs(row)

    Enum.any?([
      attrs["date_text"],
      attrs["venue"],
      attrs["venue_type"],
      attrs["note"],
      companies[company_id(row)]
    ])
  end

  defp company_id(row), do: value(row, "_k_IdCompaniaNombre")

  # A performance whose date gives no year (`Performance.years/1`) is kept, and ordered last:
  # the report lists it.
  defp undated(described) do
    for {row, plays} <- described,
        play <- plays,
        Performance.years(value(row, "ObrRep_Fecha")) == {nil, nil},
        do: label(play, row, value(row, "ObrRep_Fecha"))
  end

  # "EMOTHE0153 T11:240: 1597-9": FileMaker's id, for a person to find the row by.
  defp label(play, row, detail \\ nil) do
    ["#{play.code} T11:#{row["_kp_IdObraRepresentacion"]}", detail]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(": ")
  end

  # --- places

  # Each described performance's T10 link, resolved by S9b's rules: the places the plan
  # needs and, by performance id, a performance's place and state.
  defp lookup_places(data, described) do
    ids = MapSet.new(described, fn {row, _plays} -> row["_kp_IdObraRepresentacion"] end)

    links =
      data.places.links
      |> Enum.filter(&MapSet.member?(ids, &1["_k_IdObraRepresentacion"]))
      |> sorted("_kp_IdObraAccionLugar")
      |> Enum.uniq_by(& &1["_k_IdObraRepresentacion"])

    placed = Places.place_plan(data.places, links)

    by_performance =
      for link <- links,
          {:ok, resolved} <- [Map.fetch(placed.resolved, Places.ref(link))],
          into: %{},
          do: {link["_k_IdObraRepresentacion"], resolved}

    {Map.delete(placed, :resolved), by_performance}
  end

  # --- companies and actors

  # Each company's name by id, and the companies FileMaker keeps under two records: the
  # lowest id of those spelling a name, ignoring case, names them all.
  defp lookup_companies(data) do
    records =
      for row <- sorted(data.companies, "_kp_IdCompaniaNombre"),
          name = value(row, "ComNom_NombreCompania"),
          do: {row["_kp_IdCompaniaNombre"], name}

    groups = Enum.group_by(records, fn {_id, name} -> String.downcase(name) end)

    %{
      names:
        Map.new(records, fn {id, name} ->
          [{_first, canonical} | _] = groups[String.downcase(name)]
          {id, canonical}
        end),
      twins: for({_key, [{_id, name}, _ | _] = group} <- groups, do: {name, ids(group)})
    }
  end

  # An actor is who their three names say, ignoring case, whatever their sex: FileMaker's
  # twins are one actor, with the sex of whichever twin has one. By record id.
  defp lookup_actors(data) do
    sexes = Map.new(data.sexes, fn {id, word} -> {id, @sexes[word]} end)

    records =
      for row <- sorted(data.actors, "_kp_IdActorNombre"),
          actor = actor(row, sexes),
          do: {row["_kp_IdActorNombre"], actor}

    groups = Enum.group_by(records, fn {_id, actor} -> identity(actor) end)

    canonical =
      Map.new(groups, fn {identity, [{_id, first} | _] = group} ->
        sex = Enum.find_value(group, fn {_id, actor} -> actor["sex"] end)
        {identity, %{first | "sex" => sex}}
      end)

    %{
      by_id: Map.new(records, fn {id, actor} -> {id, canonical[identity(actor)]} end),
      twins:
        for(
          {identity, [_, _ | _] = group} <- groups,
          do: {actor_name(canonical[identity]), ids(group)}
        )
    }
  end

  # An actor with no name at all is no actor. A forename alone ("Rosimond") is the name they
  # went by: `Actor`'s nickname.
  defp actor(row, sexes) do
    surname = value(row, "ActNom_Apellidos")
    forename = value(row, "ActNom_Nombre")
    nickname = value(row, "ActNom_Apodo")

    {forename, nickname} =
      if surname || nickname, do: {forename, nickname}, else: {nil, forename}

    if surname || nickname do
      %{
        "surname" => surname,
        "forename" => forename,
        "nickname" => nickname,
        "sex" => sexes[value(row, "_k_IdActorSexo")]
      }
    end
  end

  defp identity(%Actor{} = actor),
    do:
      identity(%{
        "surname" => actor.surname,
        "forename" => actor.forename,
        "nickname" => actor.nickname
      })

  defp identity(actor),
    do: for(field <- ~w(surname forename nickname), do: String.downcase(actor[field] || ""))

  defp actor_name(actor) do
    Actor.display_name(%Actor{
      surname: actor["surname"],
      forename: actor["forename"],
      nickname: actor["nickname"]
    })
  end

  defp ids(group), do: Enum.map(group, &elem(&1, 0))

  # The twins a plan uses, by name: those with a record some performance names.
  defp merged(twins, used) do
    for({name, ids} <- twins, Enum.any?(ids, &MapSet.member?(used, &1)), do: name)
    |> Enum.sort()
  end

  defp reused_companies(names) do
    have = MapSet.new(Performances.list_companies(), &String.downcase(&1.name))
    Enum.filter(names, &MapSet.member?(have, String.downcase(&1)))
  end

  defp reused_actors(people) do
    have = MapSet.new(Performances.list_actors(), &identity/1)
    Enum.filter(people, &MapSet.member?(have, identity(&1)))
  end

  # --- cast

  # Each performance's cast as `%{actor: attrs, role: role}` in FileMaker's order. A cast row's
  # actor key ends in "|" ("6|"); the picker leftovers ("1|Actor38|") name no actor.
  defp lookup_cast(data, described, actors) do
    roles = Map.new(data.roles, &{&1["_kp_IdActorRol"], value(&1, "ActRol_Nombre")})

    rows =
      data.cast
      |> sorted("_kp_IdActorRepresentacion")
      |> Enum.group_by(& &1["_k_IdObraRepresentacion"])

    {known, unknown} =
      for {row, [play | _]} <- described,
          member <- Map.get(rows, row["_kp_IdObraRepresentacion"], []) do
        {play, row, member, String.replace_suffix(member["_k_IdActorNombre"], "|", "")}
      end
      |> Enum.split_with(fn {_play, _row, _member, key} -> Map.has_key?(actors, key) end)

    %{
      by_performance:
        Enum.group_by(
          known,
          fn {_play, row, _member, _key} -> row["_kp_IdObraRepresentacion"] end,
          fn {_play, _row, member, key} ->
            %{actor: actors[key], role: roles[value(member, "_k_IdActorRol")]}
          end
        ),
      used: MapSet.new(known, fn {_play, _row, _member, key} -> key end),
      skipped:
        for(
          {play, row, member, _key} <- unknown,
          do: label(play, row, "cast row #{member["_k_IdActorNombre"]}")
        )
    }
  end

  # --- sources

  # The work each cited record belongs to (`@works`, else a work of its own), the works as
  # entries, and each performance's source with its own volume and pages. A record T13 does
  # not have, or that names nothing, is no source.
  defp lookup_sources(data, described) do
    lookups = ImportBibliography.lookups(data)
    records = Map.new(data.sources, &{&1["_kp_IdFuenteInformacion"], &1})

    cited =
      for(
        {row, _plays} <- described,
        id = value(row, "_k_IdFuenteInformacion"),
        uniq: true,
        do: id
      )
      |> Enum.sort_by(&number/1)

    resolved = Map.new(cited, &{&1, resolve(&1, records[&1], lookups)})
    works = build_works(cited, resolved, existing_refs())

    by_performance =
      for {row, _plays} <- described,
          id = value(row, "_k_IdFuenteInformacion"),
          {:ok, key, _attrs} <- [resolved[id]],
          into: %{},
          do: {row["_kp_IdObraRepresentacion"], source(key, works[key], records[id])}

    skipped =
      for {row, [play | _]} <- described,
          id = value(row, "_k_IdFuenteInformacion"),
          {:skip, why} <- [resolved[id]],
          do: label(play, row, why)

    %{works: works, by_performance: by_performance, skipped: skipped}
  end

  defp resolve(id, nil, _lookups), do: {:skip, "T13:#{id} is not in FileMaker"}

  defp resolve(id, record, lookups) do
    if work = @work_of[id] do
      {:ok, work, nil}
    else
      attrs = entry_attrs(id, record, lookups)

      if Entry.named?(attrs),
        do: {:ok, "T13:" <> id, attrs},
        else: {:skip, "T13:#{id} names nothing"}
    end
  end

  # T13 reads as T12.1 under another prefix: `Import.Bibliography.record_attrs/2` reads it,
  # then the hand lists have their say.
  defp entry_attrs(id, record, lookups) do
    attrs = record |> bibliography_row() |> ImportBibliography.record_attrs(lookups)
    attrs = if id in @catalogues, do: %{attrs | kind: "catalogue"}, else: attrs

    attrs |> Map.merge(Map.get(@notes, id, %{})) |> Map.merge(Map.get(@named, id, %{}))
  end

  defp bibliography_row(record),
    do: Map.new(record, fn {key, text} -> {rename(key), clean(text) || ""} end)

  defp rename("FueInf_" <> field), do: "BibSel_" <> field
  defp rename("_k_IdFuenteInfoTipo"), do: "_k_IdBiblioSelTipo"
  defp rename(key), do: key

  # One entry per work, its records in id order. `existing` is the edition S4 brought in
  # that the hand list sends a record to, when Playcode has it; `identical` an entry
  # Playcode has that cites the work as it would be created.
  defp build_works(cited, resolved, present) do
    members =
      for id <- cited, {:ok, key, attrs} <- [resolved[id]], do: {key, id, attrs}

    works =
      members
      |> Enum.group_by(&elem(&1, 0))
      |> Map.new(fn {key, [{_key, first, attrs} | _] = group} ->
        existing = @existing[first]

        {key,
         %{
           attrs: work_attrs(key, attrs),
           existing: if(existing in present, do: existing),
           records: Enum.map(group, &elem(&1, 1)),
           ref: "T13:" <> first
         }}
      end)

    created = for {key, %{existing: nil, attrs: attrs}} <- works, do: {key, description(attrs)}
    found = Bibliography.identical_entries(Enum.map(created, &elem(&1, 1)), nil)
    identical = Map.new(created, fn {key, description} -> {key, found[description]} end)

    Map.new(works, fn {key, work} -> {key, Map.put(work, :identical, identical[key])} end)
  end

  defp work_attrs(key, attrs) do
    case @works[key] do
      nil -> attrs
      work -> Map.put(work.attrs, :kind, work.kind)
    end
  end

  defp description(attrs), do: Entry.description(struct(Entry, attrs))

  # Where a performance sits in a work shared by many records, or in an edition Playcode has
  # already, is its own record's volume and pages; a work of its own keeps them on the entry.
  defp source(key, work, record) do
    if Map.has_key?(@works, key) or work.existing,
      do: {key, volume(record), value(record, "FueInf_Pag")},
      else: {key, nil, nil}
  end

  defp volume(record),
    do: value(record, "FueInf_NumVolTomo") || title_volume(value(record, "FueInf_Titulo2"))

  # "Volume 5: 1603-1608" is 5, "Volume IX" 9.
  defp title_volume(nil), do: nil

  defp title_volume(title) do
    case Regex.run(~r/\bVolume\s+(\d+|[IVXLC]+)\b/, title, capture: :all_but_first) do
      [number] -> if number =~ ~r/\A\d+\z/, do: number, else: number |> arabic() |> to_string()
      nil -> nil
    end
  end

  defp arabic(roman) do
    for(<<letter <- roman>>, do: @roman[letter])
    |> Enum.chunk_every(2, 1, [0])
    |> Enum.sum_by(fn [this, next] -> if this < next, do: -this, else: this end)
  end

  defp existing_refs do
    Entry
    |> where([e], e.filemaker_id in ^Map.values(@existing))
    |> select([e], e.filemaker_id)
    |> Repo.all()
  end

  # --- the report

  @doc "The plan as lines of text, for the mix task and the release."
  def report(plan) do
    names = Places.place_names(plan.places)

    per_play =
      for performance <- Enum.sort_by(plan.performances, & &1.code),
          do: line(performance, plan.works, names)

    plays = plan.performances |> Enum.uniq_by(& &1.play_id) |> length()

    skipped =
      for {title, reason} <- [
            {"performances saying nothing", :empty},
            {"dates without a year", :undated},
            {"cast rows without an actor", :cast},
            {"sources", :source},
            {"places", :place}
          ],
          line <- section("skipped, #{title}", plan.skipped[reason]),
          do: line

    per_play ++
      ["", "performances: #{length(plan.performances)} on #{plays} plays"] ++
      section("companies to create", plan.companies -- plan.reused_companies) ++
      section("companies reused", plan.reused_companies) ++
      section("companies merged", plan.merged_companies) ++
      section("actors to create", Enum.map(plan.actors -- plan.reused_actors, &actor_name/1)) ++
      section("actors reused", Enum.map(plan.reused_actors, &actor_name/1)) ++
      section("actors merged", plan.merged_actors) ++
      entries(plan.works) ++
      Places.place_report(plan) ++
      skipped ++
      [
        "performances on versions not held: #{plan.not_held}",
        "already imported: #{length(plan.already_imported)} plays #{Enum.join(plan.already_imported, ", ")}"
      ]
  end

  defp section(title, lines), do: ["#{title}: #{length(lines)}" | Enum.map(lines, &("  " <> &1))]

  # `EMOTHE0304  1610  Globe or Blackfriars · The King’s Men · commercial theatre [Wiggins 6, 83]`
  defp line(performance, works, names) do
    attrs = performance.attrs
    type = attrs["venue_type"] && Performance.venue_type_label(attrs["venue_type"], "en")
    place = for key <- [performance.place, performance.state], key, do: names[key]

    parts =
      [attrs["venue"], Enum.join(place, " — "), performance.company, type]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" · ")

    [performance.code, attrs["date_text"], parts, source_label(performance, works)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("  ")
  end

  defp source_label(%{source: nil}, _works), do: nil

  defp source_label(performance, works) do
    where = [performance.source_volume, performance.source_pages] |> Enum.reject(&is_nil/1)

    "[" <>
      String.trim("#{work_label(works[performance.source])} #{Enum.join(where, ", ")}") <> "]"
  end

  # The first author's surname, else the title: how a person finds the work in the report.
  defp work_label(%{attrs: attrs}) do
    case attrs[:analytic_author] || attrs[:monogr_author] do
      nil -> attrs[:monogr_title] || attrs[:analytic_title]
      author -> author |> String.split(",") |> hd()
    end
  end

  defp entries(works) do
    {reused, created} =
      works
      |> Enum.sort_by(fn {_key, work} -> number(hd(work.records)) end)
      |> Enum.split_with(fn {_key, work} -> work.existing || work.identical end)

    section("entries to create", Enum.map(created, &entry_line/1)) ++
      section("entries reused", Enum.map(reused, &entry_line/1))
  end

  defp entry_line({_key, work}) do
    title = work.attrs[:monogr_title] || work.attrs[:analytic_title]

    "#{Enum.join(Enum.uniq([work_label(work), title]), " · ")} (T13:#{Enum.join(work.records, ", ")})" <>
      if(work.existing, do: " → #{work.existing}", else: "")
  end

  # --- reading FileMaker

  # A field's text as the import copies it: whitespace as a TEI file gives it back, and
  # nothing for a blank and for FileMaker's own filler, "{Falta año pub}" and the like.
  defp value(row, field), do: clean(row[field])

  defp clean(text) do
    case Text.squeeze(text) do
      nil -> nil
      text -> if text =~ ~r/\A\{[^{}]*\}\z/, do: nil, else: text
    end
  end

  defp sorted(rows, id_field), do: Enum.sort_by(rows, &number(&1[id_field]))

  defp number(id), do: String.to_integer(id)

  # A play is done once the import has written to it. Its filemaker performances alone are no
  # marker: a curator may delete every one, and the next run must not bring them back. The
  # activity-log row the import writes per play survives that.
  defp imported_play_ids do
    logged =
      ActivityLog.Entry
      |> where([a], a.action == "import" and a.resource_type == "play_performance")
      |> where([a], fragment("?->>'source'", a.metadata) == "filemaker")
      |> select([a], a.play_id)

    Performance
    |> where([p], p.origin == "filemaker")
    |> select([p], p.play_id)
    |> union(^logged)
    |> Repo.all()
    |> MapSet.new()
  end
end
