defmodule Playcode.Import.Places do
  @moduledoc """
  The one-time move of FileMaker's places of action into Playcode (S9b). Spec: "The import"
  in docs/superpowers/specs/2026-10-19-s9b-places-import-design.md, whose rules 1-8 under
  "From FileMaker records to places" this module follows.

  `load/1` reads the T10 tables. `plan/2` decides what to write: it reads the database but
  never writes. `report/1` prints the plan.

  FileMaker keeps one table per level (`T10.1` continents to `T10.5` vague places), and each
  record carries the ids of the places around it, so a new record is made whenever the
  country around a place changes: Rome is five records. A record is named here by
  `{level, id}`, 1 a continent to 5 a vague place, since ids collide across levels. `T10.X`
  pairs a historical record (its names `esHistorico`) with a modern one. The plan makes one
  place per real place, the *referent* of each record: a historical record's modern twin,
  to which it adds its own names as historical ones. A historical country that shares no
  name with its twin is a historical state, a place of its own under its continent.

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

  # Today's parent where FileMaker's modern record lacks the country.
  @parents %{
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

  # bosque pastoril, Una isla: no real referent, one place shared by every play using it.
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
  def load(dir) do
    Enum.reduce_while(@files, {:ok, %{}}, fn {key, file}, {:ok, data} ->
      case FilemakerXml.read(Path.join(dir, file)) do
        {:ok, rows} -> {:cont, {:ok, Map.put(data, key, rows)}}
        {:error, reason} -> {:halt, {:error, {file, reason}}}
      end
    end)
  end

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
  whole. A performance's links are not a version's: they wait for the performances (S5).

  The rest are report lines: `merged`, the merges that bring a name the place lacks
  ("Elsinore → Helsingør"); `twinless`, historical records with no modern twin and no entry
  in the hand lists; `no_country`, places with no country between them and their continent;
  `reused`.
  """
  def plan(data, plays) do
    world = world(data)
    imported = imported_play_ids()
    by_code = Enum.group_by(plays, &Play.short_code(&1.code))

    empty = %{
      candidates: [],
      skipped: %{no_place: [], empty: [], duplicate: [], nameless: []},
      already_imported: MapSet.new(),
      not_held: 0
    }

    acc =
      data.links
      |> Enum.filter(&id(&1, "_k_IdObraTitulo"))
      |> Enum.sort_by(&String.to_integer(&1["_kp_IdObraAccionLugar"]))
      |> Enum.reduce(empty, fn row, acc ->
        case Map.get(by_code, version_code(row["_k_IdObraTitulo"]), []) do
          [] -> %{acc | not_held: acc.not_held + 1}
          plays -> Enum.reduce(plays, acc, &take(&2, world, imported, row, &1))
        end
      end)

    candidates = Enum.reverse(acc.candidates)
    roots = roots(candidates)
    places = places(world, roots)
    {links, duplicates} = deduplicate(candidates, places)

    # A duplicate may have been the only link to reach a record: plan without it.
    {roots, places} =
      case roots(links) do
        ^roots -> {roots, places}
        fewer -> {fewer, places(world, fewer)}
      end

    %{
      places: places,
      links: Enum.map(links, &elem(&1, 0)),
      skipped:
        acc.skipped
        |> Map.new(fn {reason, labels} -> {reason, Enum.reverse(labels)} end)
        |> Map.put(:duplicate, duplicates),
      not_held: acc.not_held,
      already_imported: acc.already_imported |> MapSet.to_list() |> Enum.sort(),
      merged: merged(world, roots),
      twinless: for(key <- roots, twinless?(world, key), do: describe(world, key)),
      no_country: no_country(world, places),
      reused: reused(world, places)
    }
  end

  @doc "The plan as lines of text, for the mix task and the release."
  def report(plan) do
    by_key = Map.new(plan.places, &{&1.key, &1})
    name = &place_name(by_key[&1])

    per_play =
      for link <- Enum.sort_by(plan.links, & &1.code) do
        "#{link.code}  #{name.(link.place)}" <>
          if(link.state, do: " — #{name.(link.state)}", else: "")
      end

    to_create =
      for %{existing: nil} = place <- plan.places do
        "#{name.(place.key)} (#{place.attrs["type"]})" <>
          if(place.parent, do: " in #{name.(place.parent)}", else: "")
      end

    plays = plan.links |> Enum.uniq_by(& &1.play_id) |> length()

    skipped =
      for {reason, labels} <- Enum.sort(plan.skipped),
          line <- section("skipped, #{reason}", labels),
          do: line

    per_play ++
      ["", "links: #{length(plan.links)} on #{plays} plays"] ++
      section("places to create", to_create) ++
      section("places reused", plan.reused) ++
      section("merged", plan.merged) ++
      section("twinless", plan.twinless) ++
      section("no country", plan.no_country) ++
      skipped ++
      [
        "links on versions not held: #{plan.not_held}",
        "already imported: #{length(plan.already_imported)} plays #{Enum.join(plan.already_imported, ", ")}"
      ]
  end

  defp section(title, lines), do: ["#{title}: #{length(lines)}" | Enum.map(lines, &("  " <> &1))]

  defp place_name(%{existing: %Place{} = place}), do: Places.display_name(place, "es")
  defp place_name(%{attrs: %{"names" => [first | _]}}), do: first["name"]

  # A FileMaker link on `play`: a candidate link with its label and the records it
  # reaches, or a skipped one; nothing for a play already imported.
  defp take(acc, world, imported, row, play) do
    if MapSet.member?(imported, play.id) do
      %{acc | already_imported: MapSet.put(acc.already_imported, play.code)}
    else
      case linked_place(world, row) do
        {:ok, deepest, place} ->
          link = %{
            play_id: play.id,
            code: play.code,
            place: place,
            state: state(world, row, deepest),
            note: value(row["espacio"]),
            ref: "T10:" <> row["_kp_IdObraAccionLugar"]
          }

          reached =
            Enum.filter(chain(row) ++ [place, link.state], &Map.has_key?(world.records, &1))

          %{acc | candidates: [{link, link_label(row), reached} | acc.candidates]}

        {:skip, reason} ->
          %{acc | skipped: Map.update!(acc.skipped, reason, &[link_label(row) | &1])}
      end
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

  # The records the links reach, each once, in the order first reached.
  defp roots(candidates), do: candidates |> Enum.flat_map(&elem(&1, 2)) |> Enum.uniq()

  # A play links a place once (the unique index): a later link to a place the play
  # already has, from FileMaker or by hand, is a duplicate, its note joining the first's.
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
      Enum.reduce(candidates, {[], []}, fn {link, label, _reached} = candidate,
                                           {kept, duplicates} ->
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

  defp join_note({link, label, reached}, note) do
    joined = [link.note, note] |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
    {%{link | note: value(joined)}, label, reached}
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
        |> Enum.reject(&(&1.name == ""))
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
    %{
      record: {String.to_integer(row["_k_IdTipoToponimo"]), row["_k_IdToponimo"]},
      name: row["nombreToponimo"],
      language: @languages[row["_k_IdIdioma"]],
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

  # FileMaker's line for a link, for a person to find it by: "EMOTHE0367 T10:1083: ( unspecified ) …".
  defp link_label(row) do
    text =
      [row["denominacionAntigua"], row["espacio"]] |> Enum.map(&value/1) |> Enum.reject(&is_nil/1)

    "#{version_code(row["_k_IdObraTitulo"])} T10:#{row["_kp_IdObraAccionLugar"]}: #{Enum.join(text, " ")}"
  end

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

  # The play code FileMaker's version id stands for: 38 is EMOTHE0038.
  defp version_code(version) do
    case Integer.parse(version || "") do
      {number, ""} -> "EMOTHE" <> String.pad_leading(Integer.to_string(number), 4, "0")
      _other -> nil
    end
  end
end
