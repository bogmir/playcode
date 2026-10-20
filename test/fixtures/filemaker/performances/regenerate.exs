# Rebuilds the performances sample in this directory from the git-ignored FileMaker dump: the
# T11 rows of the versions below, their cast, actors, roles, companies and sources, the lookups
# those sources reach (T13.1, T13.2), and the T10 rows naming a kept performance, with every
# toponym record they reach, closed over each record's parents and over T10.X as the places
# sample is (test/fixtures/filemaker/places/regenerate.exs, whose hand-listed records are
# repeated here). Rows are copied byte for byte and FOUND rewritten. Run from the repository
# root:
#
#     mix run --no-start test/fixtures/filemaker/performances/regenerate.exs
#
# One version per rule (docs/superpowers/specs/2026-10-19-s5-performances-design.md, "From
# FileMaker rows to performances" and "From FileMaker source records to entries"):
#
#   0010  Hamlet: a venue type alone (performance 26, no date); Child's chapter (record 39,
#         kept pages); the Duke's Company (30), whose twin 52 is kept with it
#   0304  The Tempest (Wiggins's volume 6 in the title, then in NumVolTomo): every Wiggins
#         record one work, each performance with its volume and pages
#   0313  The Way of the World: the 1700 performance (145) whose cast is the cast list
#   0379  CATCOM's record 119, and its credit line typed after the venue (performance 164)
#   0671  CATCOM's record 468, beside 119; a performance with a place (Nápoles, in its state)
#   0491  record 479, a bare URL to data.bnf.fr
#   0675  a cast row with no actor (performance 358's picker leftover), roles
#   0714  Molière's cast with nicknames, a forename alone (Rosimond), the Troupe du Roi
#   0038  a performance that says nothing (159)
#   0209  record 105, which T13 does not have
#   0309, 0472, 0373  records 97, 98 and 81, the editions S4 brought in (T04:116, T04:385, T04:418)
#   0420  record 96, whose note is a series
#   0644  record 102 and 481, catalogues of their own
#   0274  Mora Sena's seven records, one work
#   0083  a version no play holds

alias Playcode.Import.FilemakerXml

dump = "doc/ctce_dades"
out = Path.dirname(__ENV__.file)

versions = ~w(10 304 313 379 491 671 675 714 38 209 309 472 373 420 644 274 83)
editions = ~w(81 97 98)

read = fn file ->
  {:ok, rows} = FilemakerXml.read(Path.join(dump, file))
  rows
end

# Keeps the rows of `file` whose values (by field name) satisfy `keep?`, and rewrites FOUND.
keep = fn file, keep? ->
  xml = File.read!(Path.join(dump, file))

  names =
    ~r/<FIELD [^>]*NAME="([^"]+)"/ |> Regex.scan(xml, capture: :all_but_first) |> List.flatten()

  [head, rest] = String.split(xml, "<RESULTSET", parts: 2)
  [_found, rows] = String.split(rest, ">", parts: 2)

  kept_rows =
    ~r{<ROW [^>]*>.*?</ROW>}s
    |> Regex.scan(rows)
    |> List.flatten()
    |> Enum.filter(fn row ->
      ~r{<COL>(.*?)</COL>}s
      |> Regex.scan(row, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.replace(&1, ~r{</?DATA>}, ""))
      |> then(&Map.new(Enum.zip(names, &1)))
      |> keep?.()
    end)

  File.write!(
    Path.join(out, file),
    head <>
      ~s(<RESULTSET FOUND="#{length(kept_rows)}">) <>
      Enum.join(kept_rows) <> "</RESULTSET></FMPXMLRESULT>"
  )
end

performances =
  Enum.filter(read.("T11_ObraRepresentacion.xml"), &(&1["_k_IdObraTitulo"] in versions))

performance_ids = MapSet.new(performances, & &1["_kp_IdObraRepresentacion"])

cast =
  Enum.filter(
    read.("T11.1_ActorRepresentacion.xml"),
    &(&1["_k_IdObraRepresentacion"] in performance_ids)
  )

# A cast row's actor key ends in "|" ("6|"); a picker leftover is "1|Actor38|".
actor_id = fn row -> String.trim_trailing(row["_k_IdActorNombre"], "|") end

# The records FileMaker keeps twice (one person or company, two spellings): both are kept, so
# the plan's merge has both.
identity = fn names -> Enum.map(names, &String.downcase(&1 || "")) end
all_actors = read.("T11.11_ActorNombre.xml")
actor_names = &identity.([&1["ActNom_Apellidos"], &1["ActNom_Nombre"], &1["ActNom_Apodo"]])
cited_actors = MapSet.new(cast, actor_id)

actor_twins =
  all_actors
  |> Enum.filter(&(&1["_kp_IdActorNombre"] in cited_actors))
  |> MapSet.new(actor_names)

all_companies = read.("T11.3_CompaniaNombre.xml")
company_name = &String.downcase(&1["ComNom_NombreCompania"])
cited_companies = MapSet.new(performances, & &1["_k_IdCompaniaNombre"])

company_twins =
  all_companies
  |> Enum.filter(&(&1["_kp_IdCompaniaNombre"] in cited_companies))
  |> MapSet.new(company_name)

sources =
  performances
  |> Enum.map(& &1["_k_IdFuenteInformacion"])
  |> Enum.concat(editions)
  |> MapSet.new()

source_rows =
  Enum.filter(read.("T13_FuenteInformacion.xml"), &(&1["_kp_IdFuenteInformacion"] in sources))

cities = MapSet.new(source_rows, & &1["_k_IdCiudad"])
publishers = MapSet.new(source_rows, & &1["_k_IdEditorial"])

keep.("T11_ObraRepresentacion.xml", &(&1["_k_IdObraTitulo"] in versions))
keep.("T11.1_ActorRepresentacion.xml", &(&1["_k_IdObraRepresentacion"] in performance_ids))

keep.(
  "T11.11_ActorNombre.xml",
  &(&1["_kp_IdActorNombre"] in cited_actors or actor_names.(&1) in actor_twins)
)

roles = MapSet.new(cast, & &1["_k_IdActorRol"])
keep.("T11.22_ActorRol.xml", &(&1["_kp_IdActorRol"] in roles))

keep.(
  "T11.3_CompaniaNombre.xml",
  &(&1["_kp_IdCompaniaNombre"] in cited_companies or
      (&1["ComNom_NombreCompania"] != "" and company_name.(&1) in company_twins))
)

keep.("T13_FuenteInformacion.xml", &(&1["_kp_IdFuenteInformacion"] in sources))
keep.("T13.1_Ciudad.xml", &(&1["_kp_IdCiudad"] in cities))
keep.("T13.2_Editorial.xml", &(&1["_kp_IdEditorial"] in publishers))
File.cp!(Path.join(dump, "T11.12_ActorSexo.tab"), Path.join(out, "T11.12_ActorSexo.tab"))

# --- T10: the places of the kept performances, as test/fixtures/filemaker/places cuts them.

# Every record named in Playcode.Import.Places' hand lists, so each resolves here.
hand_listed =
  for {level, ids} <- [
        {2, ~w(1164 1168 1171 1177 1186 1198 1219 1367 1378 1382 1385 1387 1393 1398 1412)},
        {3, ~w(115 116 118 137 138 139)},
        {4,
         ~w(70 77 92 110 111 113 132 133 134 138 139 152 156 159 161 163 170 172 181 182 183 184 185 198 200 201 202 203 207 208 215 219)},
        {5, ~w(82 84 85 87 89 91 98 102 104 105)}
      ],
      id <- ids,
      do: {level, id}

tables = [
  {1, "T10.1_Continente.xml", "_kp_IdContinente"},
  {2, "T10.2_Pais.xml", "_kp_IdPais"},
  {3, "T10.3_Region.xml", "_kp_IdRegion"},
  {4, "T10.4_Ciudad.xml", "_kp_IdCiudad"},
  {5, "T10.5_Locvaga.xml", "_kp_IdLocvaga"}
]

# The records a row names, as the importer reads them.
chain = fn row ->
  for {level, field} <- [
        {5, "_k_IdLocvaga"},
        {4, "_k_IdCiudad"},
        {3, "_k_IdRegion"},
        {2, "_k_IdPais"},
        {1, "_k_IdContinente"}
      ],
      (row[field] || "") != "",
      do: {level, row[field]}
end

records =
  for {level, file, id} <- tables, row <- read.(file), into: %{}, do: {{level, row[id]}, row}

pairs = read.("T10.X_TopoRelacion.xml")
pair_key = fn pair, side -> {String.to_integer(pair["_k_IdTipoToponimo"]), pair[side]} end

links =
  Enum.filter(
    read.("T10_ObraAccionLugar.xml"),
    &(&1["_k_IdObraRepresentacion"] in performance_ids)
  )

close = fn close, kept ->
  grown =
    kept
    |> Enum.flat_map(&chain.(Map.get(records, &1, %{})))
    |> Enum.concat(
      for pair <- pairs,
          pair_key.(pair, "_k_IdToponimoHistorico") in kept,
          do: pair_key.(pair, "_k_IdToponimoActual")
    )
    |> MapSet.new()
    |> MapSet.union(kept)

  if grown == kept, do: kept, else: close.(close, grown)
end

kept = close.(close, MapSet.new(Enum.flat_map(links, chain) ++ hand_listed))

keep.("T10_ObraAccionLugar.xml", &(&1["_k_IdObraRepresentacion"] in performance_ids))
for {level, file, id} <- tables, do: keep.(file, &({level, &1[id]} in kept))

keep.(
  "T10.11_NombreToponimo.xml",
  &({String.to_integer(&1["_k_IdTipoToponimo"]), &1["_k_IdToponimo"]} in kept)
)

keep.("T10.X_TopoRelacion.xml", &(pair_key.(&1, "_k_IdToponimoHistorico") in kept))

IO.puts("wrote the performances sample to #{out}: #{length(performances)} performances")
