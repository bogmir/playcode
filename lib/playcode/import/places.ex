defmodule Playcode.Import.Places do
  @moduledoc """
  The one-time move of FileMaker's places of action into Playcode (S9b). Spec: "The import"
  in docs/superpowers/specs/2026-10-19-s9b-places-import-design.md, whose rules 1-8 under
  "From FileMaker records to places" this module follows.

  `load/1` reads the T10 tables. `plan/2` decides what to write: it reads the database but
  never writes. `report/1` prints the plan and `apply_plan/2` writes it. The rules that turn
  a T10 link into a place and a state belong to no owner: `place_plan/2` and `apply_places/1`
  serve a play version's links here and a performance's (S5) in `Import.Performances`.

  FileMaker keeps one table per level (`T10.1` continents to `T10.5` vague places), and each
  record carries the ids of the places around it, so a new record is made whenever the
  country around a place changes: Rome is five records. A record is named here by
  `{level, id}`, 1 a continent to 5 a vague place, since ids collide across levels. `T10.X`
  pairs a historical record (its names `esHistorico`) with a modern one. The plan makes one
  place per real place, the *referent* of each record: a historical record's modern twin,
  to which it adds its own names as historical ones. A historical country that shares no
  name with its twin is a historical state, a place of its own under its continent. A name
  FileMaker misspelt is read as corrected by hand (`@names`).

  Each FileMaker link on a play we hold becomes a link to the place, with the state the
  place was in, in that play. A play the import has written to before (a `filemaker` link,
  or its "import" row in the activity log, which outlives the links) is skipped whole, so
  a curator's deletions stick.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Catalogue.Play
  alias Playcode.Import.FilemakerXml
  alias Playcode.Places
  alias Playcode.Places.Place
  alias Playcode.Places.PlayPlace
  alias Playcode.Repo

  @default_dir "doc/ctce_dades"

  @files [
    links: "T10_ObraAccionLugar.xml",
    names: "T10.11_NombreToponimo.xml",
    pairs: "T10.X_TopoRelacion.xml",
    continents: "T10.1_Continente.xml",
    countries: "T10.2_Pais.xml",
    regions: "T10.3_Region.xml",
    cities: "T10.4_Ciudad.xml",
    vague: "T10.5_Locvaga.xml"
  ]

  # A historical record's modern twin where T10.X has none.
  @twins %{
    # Elsinore → Helsingør
    {4, "113"} => {4, "92"},
    # Santarén → Santarém
    {4, "110"} => {4, "111"},
    # Faversham
    {4, "198"} => {4, "202"},
    {4, "200"} => {4, "202"},
    {4, "201"} => {4, "202"},
    {4, "203"} => {4, "202"}
  }

  # Records that are a place of their own whatever T10.X says, with their parent.
  @own %{
    # Old Ford, inside London
    {4, "152"} => {4, "70"},
    # Sardis: no modern country
    {4, "132"} => :continent,
    # Carthage: no modern country
    {4, "219"} => :continent,
    # Costa de Tarragona, in Spain
    {5, "82"} => {2, "1177"}
  }

  # Today's parent where FileMaker's modern record leaves it out.
  @parents %{
    # Amalec → Palestina
    {5, "104"} => {3, "118"},
    # Helsingør → Dinamarca
    {4, "92"} => {2, "1168"},
    # Esparta → Grecia
    {4, "183"} => {2, "1198"},
    # Mantua, Verona, Palermo, Florencia, Génova, Sicilia → Italia
    {4, "159"} => {2, "1219"},
    {4, "161"} => {2, "1219"},
    {4, "163"} => {2, "1219"},
    {4, "170"} => {2, "1219"},
    {4, "172"} => {2, "1219"},
    {4, "181"} => {2, "1219"}
  }

  # FileMaker's names as written, by record and language, and the name to read instead: its
  # spelling slips, and names nobody would print (owner's decisions, 2026-10-19). Applied
  # wherever the names are read, so a correction reaches a place whichever record brings
  # the name. nil drops the name.
  @names %{
    # the city of Algiers, for the country
    {{2, "1171"}, "es", "Argel"} => "Argelia",
    # the country, not the island
    {{2, "1186"}, "it", "Gran Bretagna"} => "Regno Unito",
    {{2, "1367"}, "en", "Castille"} => "Castile",
    {{2, "1367"}, "it", "Castilia"} => "Castiglia",
    # the Spanish name
    {{2, "1367"}, "pt", "Castilla"} => "Castela",
    {{2, "1378"}, "es", "Reino de Napoles"} => "Reino de Nápoles",
    # the historical Spain
    {{2, "1382"}, "it", "Espagna"} => "Spagna",
    # a straight apostrophe, where the Kingdom of England has ’
    {{2, "1387"}, "fr", "Royaume d'Écosse"} => "Royaume d’Écosse",
    # Bohemia: the Spanish name in three languages, and an alternate that is no Spanish
    {{2, "1393"}, "fr", "Bohemia"} => "Bohême",
    {{2, "1393"}, "it", "Bohemia"} => "Boemia",
    {{2, "1393"}, "pt", "Bohemia"} => "Boémia",
    {{2, "1393"}, "es", "Boheme"} => nil,
    # the other four languages name the kingdom
    {{2, "1398"}, "pt", "Macedónia Antiga"} => "Reino da Macedónia",
    {{2, "1412"}, "fr", "Royaum de Numidie"} => "Royaume de Numidie",
    {{3, "115"}, "fr", "Péninsule Italienne"} => "Péninsule italienne",
    {{3, "116"}, "fr", "Péninsule Italienne"} => "Péninsule italienne",
    # FileMaker has Lazio and Latium the other way round in English; Spanish is Lacio for both
    {{3, "137"}, "en", "Lazio"} => "Latium",
    {{3, "137"}, "es", "Latium"} => "Lacio",
    {{3, "138"}, "en", "Latium"} => "Lazio",
    # the historical Marches
    {{3, "139"}, "fr", "Le Marches"} => "Les Marches",
    {{3, "139"}, "it", "le Marche"} => "Le Marche",
    {{4, "77"}, "fr", "Napoles"} => "Naples",
    # the Italian name
    {{4, "77"}, "pt", "Napoli"} => "Nápoles",
    {{4, "92"}, "pt", "Helsingor"} => "Helsingør",
    {{4, "132"}, "pt", "Sárdis"} => "Sardes",
    {{4, "133"}, "pt", "Sárdis"} => "Sardes",
    {{4, "134"}, "pt", "Sárdis"} => "Sardes",
    {{4, "138"}, "pt", "Oostende"} => "Ostende",
    {{4, "139"}, "pt", "Oostende"} => "Ostende",
    # the French name, in the historical Jerusalem
    {{4, "156"}, "pt", "Jérusalem"} => "Jerusalém",
    # the Lacedaemonians, for the city
    {{4, "182"}, "it", "Lacedemoni"} => "Lacedemone",
    {{4, "184"}, "es", "Batra"} => "Bactra",
    {{4, "185"}, "es", "Balkh (o Balj)"} => "Balj",
    {{4, "207"}, "pt", "Padua"} => "Pádua",
    {{4, "208"}, "pt", "Padua"} => "Pádua",
    # Constantina: the Spanish name in three languages
    {{4, "215"}, "en", "Constantina"} => "Constantine",
    {{4, "215"}, "fr", "Constantina"} => "Constantine",
    {{4, "215"}, "it", "Constantina"} => "Costantina",
    {{4, "219"}, "pt", "Cartgao"} => "Cartago",
    # the pastoral wood, the historical record and today's, capitalised as a place's name;
    # "foresta" is Italian
    {{5, "84"}, "es", "bosque pastoril"} => "Bosque pastoril",
    {{5, "84"}, "en", "pastoral wood"} => "Pastoral wood",
    {{5, "84"}, "fr", "forêt pastoral"} => "Forêt pastorale",
    {{5, "84"}, "it", "bosco pastorale"} => "Bosco pastorale",
    {{5, "84"}, "pt", "floresta pastoral"} => "Floresta pastoral",
    {{5, "85"}, "es", "bosque pastoril"} => "Bosque pastoril",
    {{5, "85"}, "en", "pastoral wood"} => "Pastoral wood",
    {{5, "85"}, "fr", "forêt pastorale"} => "Forêt pastorale",
    {{5, "85"}, "it", "bosco pastorale"} => "Bosco pastorale",
    {{5, "85"}, "pt", "foresta pastoral"} => "Floresta pastoral",
    # Amalec, the historical record and today's
    {{5, "104"}, "en", "Amalec"} => "Amalek",
    {{5, "104"}, "pt", "Amalec"} => "Amaleque",
    {{5, "105"}, "en", "Amalec"} => "Amalek",
    {{5, "105"}, "pt", "Amalec"} => "Amaleque"
  }

  # A place's type where its level's says too little (rule 6): Old Ford, Sicilia, the Forest
  # of Arden and the pastoral wood, the Costa de Tarragona and Bosworth, Miseno, Amalec, an
  # island.
  @types %{
    {4, "152"} => "district",
    {4, "181"} => "region",
    {5, "85"} => "forest",
    {5, "89"} => "forest",
    {5, "82"} => "other",
    {5, "102"} => "other",
    {5, "87"} => "town",
    {5, "104"} => "city",
    {5, "91"} => "island"
  }

  # Bosque pastoril, Una isla: no real referent, one place shared by every play using it.
  @fictional MapSet.new([{5, "85"}, {5, "91"}])

  # sin especificar
  @no_place MapSet.new([{5, "98"}])

  # A link naming only this state is a link to that place, in that state. Othello: Cyprus,
  # then Venetian.
  @state_links %{{2, "1385"} => {2, "1164"}}

  # Each level's table and its id column.
  @levels [
    continents: {1, "_kp_IdContinente"},
    countries: {2, "_kp_IdPais"},
    regions: {3, "_kp_IdRegion"},
    cities: {4, "_kp_IdCiudad"},
    vague: {5, "_kp_IdLocvaga"}
  ]

  # The columns of a record, or a link, naming the places around it, innermost first.
  @chain [
    {5, "_k_IdLocvaga"},
    {4, "_k_IdCiudad"},
    {3, "_k_IdRegion"},
    {2, "_k_IdPais"},
    {1, "_k_IdContinente"}
  ]

  @level_types %{1 => "continent", 2 => "country", 3 => "region", 4 => "city", 5 => "other"}

  # T10.11's `_k_IdIdioma`, checked against Spain's five names.
  @languages %{"1" => "es", "2" => "fr", "3" => "en", "4" => "it", "5" => "pt"}

  # The order a place's names are planned in, by rank. The slug comes from the first.
  @language_order ~w(es en fr it pt) |> Enum.with_index() |> Map.new()

  def default_dir, do: @default_dir

  @doc "Reads the eight T10 tables from `dir`."
  def load(dir), do: FilemakerXml.read_tables(dir, @files)

  @doc """
  What the import would write. Reads the database, writes nothing. See the moduledoc.

  `places` holds one entry per place the held plays' links need, parents before children:
  its `key` (the record it is made from), the `attrs` to create it with (no slug: the
  Spanish name comes first, and `Places.create_place/1` derives it), its `parent` key, and
  the gazetteer's place it is instead, `existing`, found under any of its names. A reused
  place is never changed, so its parent is left to the gazetteer: nil here.

  `links` holds the plays' new links in FileMaker's order: the `play_id` and `code`, the
  `place` and its historical `state` (keys into `places`), the `note`, and FileMaker's
  `ref`, `"T10:<id>"`. `skipped` holds the links left out, by reason (`no_place`, `empty`,
  `duplicate`, `nameless`), as `"EMOTHE0367 T10:1083: <FileMaker's text>"`. `not_held`
  counts the links on versions we do not hold; `already_imported` names the plays skipped
  whole. A performance's links are not a version's: the performances' import plans them, through
  `place_plan/2`.

  The rest are report lines: `merged`, the merges that bring a name the place lacks
  ("Elsinore → Helsingør"); `twinless`, historical records with no modern twin and no entry
  in the hand lists; `no_country`, places with no country between them and their continent;
  `reused`.
  """
  def plan(data, plays) do
    imported = imported_play_ids()
    by_code = Enum.group_by(plays, &Play.short_code(&1.code))

    owned =
      data.links
      |> Enum.filter(&id(&1, "_k_IdObraTitulo"))
      |> Enum.sort_by(&String.to_integer(&1["_kp_IdObraAccionLugar"]))
      |> Enum.map(&{&1, Map.get(by_code, FilemakerXml.version_code(&1["_k_IdObraTitulo"]), [])})

    pending =
      for {row, plays} <- owned,
          plays = Enum.reject(plays, &MapSet.member?(imported, &1.id)),
          plays != [],
          do: {row, plays}

    placed = place_plan(data, Enum.map(pending, &elem(&1, 0)))
    {kept, duplicates} = deduplicate(candidates(pending, placed.resolved), placed.places)
    links = Enum.map(kept, &elem(&1, 0))

    # A duplicate may have been the only link to reach a record: plan without it.
    final =
      if duplicates == [] do
        placed
      else
        refs = MapSet.new(links, & &1.ref)
        place_plan(data, for({row, _plays} <- pending, MapSet.member?(refs, ref(row)), do: row))
      end

    already_imported =
      for {_row, plays} <- owned,
          play <- plays,
          MapSet.member?(imported, play.id),
          uniq: true,
          do: play.code

    final
    |> Map.drop([:resolved, :skipped])
    |> Map.merge(%{
      links: links,
      skipped: Map.put(placed.skipped, :duplicate, duplicates),
      not_held: Enum.count(owned, &match?({_row, []}, &1)),
      already_imported: Enum.sort(already_imported)
    })
  end

  @doc """
  The place rules for T10 links of any owner (rows of `T10_ObraAccionLugar`: a version's, a
  performance's). Reads the database, writes nothing, and knows no play: what a link means
  to its owner is the caller's.

  Returns `places`, the planned places as `plan/2` describes them; `resolved`, each link's
  `{place, state}` keys into `places` (state nil for none) by its `ref`, `"T10:<id>"`;
  `skipped`, the labels of the links left out, by reason (`no_place`, `empty`, `nameless`);
  and the report lines `merged`, `twinless`, `no_country` and `reused`.
  """
  def place_plan(data, rows) do
    world = world(data)
    outcomes = Enum.map(rows, &{&1, linked_place(world, &1)})

    links =
      for {row, {:ok, deepest, place}} <- outcomes do
        state = state(world, row, deepest)
        reached = Enum.filter(chain(row) ++ [place, state], &Map.has_key?(world.records, &1))
        {ref(row), {place, state}, reached}
      end

    roots = links |> Enum.flat_map(&elem(&1, 2)) |> Enum.uniq()
    places = places(world, roots)

    %{
      places: places,
      resolved: Map.new(links, fn {ref, link, _reached} -> {ref, link} end),
      skipped:
        for reason <- [:no_place, :empty, :nameless], into: %{} do
          {reason, for({row, {:skip, ^reason}} <- outcomes, do: link_label(row))}
        end,
      merged: merged(world, roots),
      twinless: for(key <- roots, twinless?(world, key), do: describe(world, key)),
      no_country: no_country(world, places),
      reused: reused(world, places)
    }
  end

  @doc """
  Writes the plan in one transaction: the places it creates, parents first, then each
  play's links in FileMaker's order (after any the play already has), then one activity-log
  entry per play, which marks the play as imported for good. Returns
  `{:ok, %{places: created, links: n}}`; a reused place is mapped, not counted.
  """
  def apply_plan(plan, opts \\ []) do
    Repo.transaction(
      fn ->
        ids = apply_places(plan.places)

        Enum.each(plan.links, &link_place!(&1, ids))

        plan.links
        |> Enum.group_by(& &1.play_id)
        |> Enum.each(fn {play_id, links} ->
          ActivityLog.log!(%{
            user_id: opts[:user_id],
            play_id: play_id,
            action: "import",
            resource_type: "play_place",
            resource_id: play_id,
            changes: %{"links" => length(links)},
            metadata: %{"source" => "filemaker"}
          })
        end)

        %{places: Enum.count(plan.places, &is_nil(&1.existing)), links: length(plan.links)}
      end,
      timeout: :infinity
    )
  end

  @doc "The plan as lines of text, for the mix task and the release."
  def report(plan) do
    name = place_names(plan.places)

    per_play =
      for link <- Enum.sort_by(plan.links, & &1.code) do
        "#{link.code}  #{name[link.place]}" <>
          if(link.state, do: " — #{name[link.state]}", else: "")
      end

    plays = plan.links |> Enum.uniq_by(& &1.play_id) |> length()

    skipped =
      for {reason, labels} <- Enum.sort(plan.skipped),
          line <- section("skipped, #{reason}", labels),
          do: line

    per_play ++
      ["", "links: #{length(plan.links)} on #{plays} plays"] ++
      place_report(plan) ++
      skipped ++
      [
        "links on versions not held: #{plan.not_held}",
        "already imported: #{length(plan.already_imported)} plays #{Enum.join(plan.already_imported, ", ")}"
      ]
  end

  @doc "A plan's places by key, each as a report names it."
  def place_names(places), do: Map.new(places, &{&1.key, place_name(&1)})

  @doc """
  The report's lines about the places themselves, for any plan with `places` and the report
  lines of `place_plan/2` (`reused`, `merged`, `twinless`, `no_country`).
  """
  def place_report(plan) do
    name = place_names(plan.places)

    to_create =
      for %{existing: nil} = place <- plan.places do
        "#{name[place.key]} (#{place.attrs["type"]})" <>
          if(place.parent, do: " in #{name[place.parent]}", else: "")
      end

    section("places to create", to_create) ++
      section("places reused", plan.reused) ++
      section("merged", plan.merged) ++
      section("twinless", plan.twinless) ++
      section("no country", plan.no_country)
  end

  @doc """
  Writes the planned places, parents first, reusing the gazetteer's where the plan found
  one. Returns each place's key mapped to its id, for the caller's links. Writes inside the
  caller's transaction.
  """
  def apply_places(places), do: Enum.reduce(places, %{}, &create_place/2)

  # `ids` maps a planned place's key to the id of the place it is in the gazetteer.
  defp create_place(%{existing: %Place{id: id}, key: key}, ids), do: Map.put(ids, key, id)

  defp create_place(%{key: key, attrs: attrs, parent: parent}, ids) do
    {:ok, place} = Places.create_place(Map.put(attrs, "parent_place_id", parent && ids[parent]))
    Map.put(ids, key, place.id)
  end

  defp link_place!(link, ids) do
    {:ok, _} =
      Places.link_place(link.play_id, ids[link.place], %{
        "historical_state_id" => link.state && ids[link.state],
        "note" => link.note,
        "role" => "setting",
        "origin" => "filemaker"
      })
  end

  defp section(title, lines), do: ["#{title}: #{length(lines)}" | Enum.map(lines, &("  " <> &1))]

  defp place_name(%{existing: %Place{} = place}), do: Places.display_name(place, "es")
  defp place_name(%{attrs: %{"names" => [first | _]}}), do: first["name"]

  # A version's resolved links, one per play holding the version, in FileMaker's order, each
  # with the label that names it in the report.
  defp candidates(pending, resolved) do
    for {row, plays} <- pending,
        {:ok, {place, state}} <- [Map.fetch(resolved, ref(row))],
        play <- plays do
      link = %{
        play_id: play.id,
        code: play.code,
        place: place,
        state: state,
        note: value(row["espacio"]),
        ref: ref(row)
      }

      {link, link_label(row)}
    end
  end

  # The place a link names, the referent of its deepest record (or of the place a state
  # it names alone stands for), or why it names none: nothing, "sin especificar", or a
  # place with no name.
  defp linked_place(world, row) do
    case chain(row) do
      [] ->
        {:skip, :empty}

      [deepest | _outer] ->
        place = referent(world, @state_links[deepest] || deepest)

        cond do
          MapSet.member?(@no_place, deepest) -> {:skip, :no_place}
          names(world, place) == [] -> {:skip, :nameless}
          true -> {:ok, deepest, place}
        end
    end
  end

  # The historical state of a link's place in its play: the state a link naming only a
  # state stands in (@state_links), else the link's country when that is a state and the
  # place lies below it, else the countryless area the link or the place's record names
  # ("Península itálica", decision 14).
  defp state(world, row, {level, _id} = deepest) do
    country = if id = id(row, "_k_IdPais"), do: {2, id}

    cond do
      Map.has_key?(@state_links, deepest) -> world.states[deepest]
      level > 2 and state?(world, country) -> world.states[country]
      level > 3 -> area(world, row, deepest)
      true -> nil
    end
  end

  defp area(world, row, deepest) do
    region = id(row, "_k_IdRegion") || id(world.records[deepest], "_k_IdRegion")
    record = region && world.records[{3, region}]

    if record && !id(record, "_k_IdPais"), do: referent(world, {3, region})
  end

  # A play links a place once (the unique index): a later link to a place the play already
  # has, from FileMaker or by hand, is a duplicate. Its note joins the first's only when that
  # is an earlier FileMaker link of this plan; a curator's link keeps its own note, and the
  # duplicate shows only as a skipped label in the report.
  defp deduplicate(candidates, places) do
    existing = Map.new(places, &{&1.key, &1.existing})
    linked = linked_places()

    # The gazetteer's place when reused, else the one the plan creates.
    same = fn link ->
      case existing[link.place] do
        nil -> {link.play_id, link.place}
        place -> {link.play_id, place.id}
      end
    end

    {kept, duplicates} =
      Enum.reduce(candidates, {[], []}, fn {link, label} = candidate, {kept, duplicates} ->
        cond do
          MapSet.member?(linked, same.(link)) ->
            {kept, [label | duplicates]}

          index = Enum.find_index(kept, &(same.(elem(&1, 0)) == same.(link))) ->
            {List.update_at(kept, index, &join_note(&1, link.note)), [label | duplicates]}

          true ->
            {[candidate | kept], duplicates}
        end
      end)

    {Enum.reverse(kept), Enum.reverse(duplicates)}
  end

  defp join_note({link, label}, note) do
    joined = [link.note, note] |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
    {%{link | note: value(joined)}, label}
  end

  # The T10 tables indexed: each record by key, its names sorted (main names in
  # @language_order, then the alternates), its T10.X twins, and the historical states.
  defp world(data) do
    world = %{
      records:
        for(
          {table, {level, id}} <- @levels,
          row <- Map.fetch!(data, table),
          into: %{},
          do: {{level, row[id]}, row}
        ),
      names:
        data.names
        |> Enum.map(&name/1)
        |> Enum.reject(&(&1.name in [nil, ""]))
        |> Enum.sort_by(&{&1.alternate, @language_order[&1.language]})
        |> Enum.group_by(& &1.record),
      twins:
        Enum.group_by(
          data.pairs,
          &pair_key(&1, "_k_IdToponimoHistorico"),
          &pair_key(&1, "_k_IdToponimoActual")
        )
    }

    Map.put(world, :states, states(world))
  end

  defp name(row) do
    record = {String.to_integer(row["_k_IdTipoToponimo"]), row["_k_IdToponimo"]}
    language = @languages[row["_k_IdIdioma"]]

    %{
      record: record,
      name: Map.get(@names, {record, language, row["nombreToponimo"]}, row["nombreToponimo"]),
      language: language,
      alternate: row["esAlternativo"] == "1",
      historical: row["esHistorico"] == "1"
    }
  end

  defp pair_key(row, side), do: {String.to_integer(row["_k_IdTipoToponimo"]), row[side]}

  # Rule 3: a historical country no modern twin shares a name with is a historical state,
  # and states sharing a name are one, keyed by the first of their records: `%{record => key}`.
  defp states(world) do
    world.records
    |> Map.keys()
    |> Enum.filter(&state_record?(world, &1))
    |> Enum.sort_by(fn {_level, id} -> String.to_integer(id) end)
    |> Enum.reduce([], fn record, states ->
      key =
        Enum.find_value(states, record, fn {other, key} ->
          same_name?(world, other, record) && key
        end)

      [{record, key} | states]
    end)
    |> Map.new()
  end

  defp state_record?(world, {2, _id} = key),
    do: historical?(world, key) and not Enum.any?(twins(world, key), &same_name?(world, &1, key))

  defp state_record?(_world, _key), do: false

  # Rule 1: the place a record stands for. The hand lists first, then T10.X.
  defp referent(world, key) do
    cond do
      Map.has_key?(@own, key) -> key
      Map.has_key?(@twins, key) -> @twins[key]
      state?(world, key) -> world.states[key]
      twin = twin(world, key) -> twin
      true -> key
    end
  end

  # A country is its twin only when they share a name (rule 3); any other record is its twin.
  defp twin(world, {2, _id} = key), do: Enum.find(twins(world, key), &same_name?(world, &1, key))
  defp twin(world, key), do: List.first(twins(world, key))

  # A historical record that stands for itself, though no hand list says so. Continents and
  # states stand for themselves by right.
  defp twinless?(world, {level, _id} = key) do
    level > 1 and historical?(world, key) and referent(world, key) == key and
      not state?(world, key) and not Map.has_key?(@own, key)
  end

  # One place per referent of the roots, in the order first reached, each after its parent.
  defp places(world, roots) do
    members = Enum.group_by(roots, &referent(world, &1))

    roots
    |> Enum.map(&referent(world, &1))
    |> Enum.uniq()
    |> Enum.reduce({MapSet.new(), []}, &visit(world, members, &1, &2))
    |> elem(1)
    |> Enum.reverse()
  end

  # Rule 8: a place the gazetteer has under any of its names is that place, and its parent
  # stays the gazetteer's. A record with no name is no place (rule 4).
  defp visit(world, members, key, {seen, places} = acc) do
    if MapSet.member?(seen, key) or names(world, key) == [] do
      acc
    else
      attrs = attrs(world, key, Map.get(members, key, []))
      existing = Enum.find_value(attrs["names"], &Places.find_by_name(&1["name"]))
      parent = if !existing, do: parent(world, key)
      acc = {MapSet.put(seen, key), places}
      {seen, places} = if parent, do: visit(world, members, parent, acc), else: acc
      {seen, [%{key: key, attrs: attrs, parent: parent, existing: existing} | places]}
    end
  end

  defp attrs(world, {level, _id} = key, members) do
    %{
      "type" => @types[key] || @level_types[level],
      "is_fictional" => MapSet.member?(@fictional, key),
      "names" => place_names(world, key, members)
    }
  end

  # Rule 4: the referent's names, each language's main one preferred, then each name a
  # record merged into it brings, as a historical one.
  defp place_names(world, key, members) do
    own = for name <- names(world, key), do: planned_name(name, not name.alternate, false)
    brought = for name <- brought_names(world, key, members), do: planned_name(name, false, true)

    Enum.with_index(own ++ brought, &Map.put(&1, "position", &2))
  end

  # The names `members` bring to the place `key`: those whose language has no name with the
  # same text yet.
  defp brought_names(world, key, members) do
    had = MapSet.new(names(world, key), &{&1.language, &1.name})

    members
    |> Enum.reject(&(&1 == key))
    |> Enum.flat_map(&names(world, &1))
    |> Enum.reject(&MapSet.member?(had, {&1.language, &1.name}))
    |> Enum.uniq_by(&{&1.language, &1.name})
  end

  defp planned_name(name, preferred, historical) do
    %{
      "name" => name.name,
      "language" => name.language,
      "is_preferred" => preferred,
      "is_historical" => historical
    }
  end

  # Rule 5, for a referent: the hand lists; a state's continent, none when its records sit
  # on several; a twinless record's continent; else the record's own, as a place.
  defp parent(world, key) do
    record = world.records[key]

    cond do
      @own[key] == :continent -> continent(record)
      hand_listed = @own[key] || @parents[key] -> hand_listed
      state?(world, key) -> state_continent(world, key)
      twinless?(world, key) -> continent(record)
      true -> around(world, record)
    end
  end

  defp state_continent(world, key) do
    case for({record, ^key} <- world.states, uniq: true, do: continent(world.records[record])) do
      [continent] -> continent
      _several -> nil
    end
  end

  # The innermost place a record names around it. The gazetteer is today's geography, so a
  # historical state there is replaced by its one modern twin, or by the continent.
  defp around(world, record) do
    case chain(record) do
      [] ->
        nil

      [key | _outer] ->
        case {state?(world, key), twins(world, key)} do
          {false, _twins} -> referent(world, key)
          {true, [twin]} -> twin
          {true, _none_or_several} -> continent(record)
        end
    end
  end

  defp continent(record), do: Enum.find(chain(record), &match?({1, _id}, &1))

  defp chain(row),
    do: for({level, field} <- @chain, (row[field] || "") != "", do: {level, row[field]})

  # The merges a person should check by eye: a record bringing a name its place lacks.
  defp merged(world, roots) do
    for key <- roots,
        place = referent(world, key),
        place != key,
        brought_names(world, place, [key]) != [],
        uniq: true,
        do: "#{label(world, key)} → #{label(world, place)}"
  end

  # Places with no country between them and their continent. Continents and countries are
  # countries enough, a fictional place is nowhere, and a reused one is the curator's.
  defp no_country(world, places) do
    by_key = Map.new(places, &{&1.key, &1})

    for place <- places,
        place.attrs["type"] != "continent",
        not place.attrs["is_fictional"],
        not in_country?(by_key, place.key),
        do: describe(world, place.key)
  end

  defp in_country?(_by_key, nil), do: false

  defp in_country?(by_key, key) do
    place = by_key[key]
    place.existing != nil or place.attrs["type"] == "country" or in_country?(by_key, place.parent)
  end

  defp reused(world, places) do
    for %{existing: %{slug: slug}} = place <- places,
        do: "#{describe(world, place.key)} → #{slug}"
  end

  # A record as the report names it: in English, else by its first name, and its table.
  defp describe(world, {level, id} = key), do: "#{label(world, key)} (T10.#{level}:#{id})"

  defp label(world, key) do
    names = names(world, key)
    (Enum.find(names, &(&1.language == "en")) || List.first(names) || %{name: "?"}).name
  end

  defp names(world, key), do: Map.get(world.names, key, [])
  defp twins(world, key), do: Map.get(world.twins, key, [])
  defp historical?(world, key), do: Enum.any?(names(world, key), & &1.historical)
  defp state?(world, key), do: Map.has_key?(world.states, key)

  defp same_name?(world, a, b) do
    not MapSet.disjoint?(
      MapSet.new(names(world, a), & &1.name),
      MapSet.new(names(world, b), & &1.name)
    )
  end

  # FileMaker's line for a link, for a person to find it by: "EMOTHE0367 T10:1083: ( unspecified ) …",
  # without the version code on a link that names none.
  defp link_label(row) do
    text =
      [row["denominacionAntigua"], row["espacio"]] |> Enum.map(&value/1) |> Enum.reject(&is_nil/1)

    label = "#{ref(row)}: #{Enum.join(text, " ")}"

    case FilemakerXml.version_code(row["_k_IdObraTitulo"]) do
      nil -> label
      code -> "#{code} #{label}"
    end
  end

  @doc "A link's reference in a plan, `\"T10:<id>\"`: the key of `place_plan/2`'s `resolved`."
  def ref(row), do: "T10:" <> row["_kp_IdObraAccionLugar"]

  defp id(row, field), do: value(row[field])

  defp value(nil), do: nil

  defp value(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end

  # A play is done once the import has written to it. Its filemaker links alone are no
  # marker: a curator may delete every one, and the next run must not bring them back. The
  # activity-log row the import writes per play survives that.
  defp imported_play_ids do
    logged =
      ActivityLog.Entry
      |> where([a], a.action == "import" and a.resource_type == "play_place")
      |> where([a], fragment("?->>'source'", a.metadata) == "filemaker")
      |> select([a], a.play_id)

    PlayPlace
    |> where([pp], pp.origin == "filemaker")
    |> select([pp], pp.play_id)
    |> union(^logged)
    |> Repo.all()
    |> MapSet.new()
  end

  # `{play_id, place_id}` for every link the plays already have.
  defp linked_places do
    PlayPlace
    |> select([pp], {pp.play_id, pp.place_id})
    |> Repo.all()
    |> MapSet.new()
  end
end
