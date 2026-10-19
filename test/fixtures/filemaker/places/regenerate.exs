# Rebuilds the place-of-action sample in this directory from the git-ignored FileMaker dump:
# the T10 links of the versions below, then every toponym record they reach, closed over
# each record's parents and over T10.X (both sides of every pair whose historical record is
# kept), plus the records the importer's hand lists name, with all their names. Rows are
# copied byte for byte and FOUND rewritten. Run from the repository root:
#
#     mix run --no-start test/fixtures/filemaker/places/regenerate.exs
#
# One play per rule (docs/superpowers/specs/2026-10-19-s9b-places-import-design.md, "From
# FileMaker records to places" and "From FileMaker links to play links"):
#
#   0007, 0038  Rome under the Papal States and the Roman Republic: one place, two states
#   0010        Elsinore merged into Helsingør by the hand list, its old names historical;
#               Helsingør given today's country by hand; the Kingdom of Denmark a state
#   0262        Old Ford, its own place inside London, though T10.X pairs it with London
#   0151        France merged with today's France; the Forest of Arden a vague place
#   0337        the Roman Republic again, on another continent: one state, no parent
#   0153, 0354  cities under a region with no country (Italian Peninsula, Ancient Greece);
#               Lacedaemon renamed Sparta
#   0005, 0006  the generic pastoral wood, one fictional place shared
#   0394, 0545  a link to a whole state (Castilla); FileMaker's free text as the note
#   0697        Othello's Venetian Cyprus, twice; a link naming only a continent
#   0367, 0653  "sin especificar", no place; an empty link
#   0418        a version no play holds
#   0201, 0231, FileMaker's spelling slips, corrected by the hand map: the Kingdom of Naples and
#   0559, 0749  Naples, Algeria (Constantina's country, Cirta in the Kingdom of Numidia),
#               Balkh (from Batra), Carthage
#   0491        Amalec, given Palestina as its parent by hand
#   0299        Bohemia, a name FileMaker gives that the hand map drops

alias Playcode.Import.FilemakerXml

dump = "doc/ctce_dades"
out = Path.dirname(__ENV__.file)

versions = ~w(5 6 7 10 38 151 153 201 231 262 299 337 354 367 394 491 545 559 653 697 749 418)

# Every record named in Playcode.Import.Places' hand lists, so each resolves here.
hand_listed =
  for {level, ids} <- [
        {2, ~w(1164 1168 1171 1177 1186 1198 1219 1367 1378 1382 1385 1393 1412)},
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

read = fn file ->
  {:ok, rows} = FilemakerXml.read(Path.join(dump, file))
  rows
end

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
links = Enum.filter(read.("T10_ObraAccionLugar.xml"), &(&1["_k_IdObraTitulo"] in versions))

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

keep.("T10_ObraAccionLugar.xml", &(&1["_k_IdObraTitulo"] in versions))

for {level, file, id} <- tables, do: keep.(file, &({level, &1[id]} in kept))

keep.(
  "T10.11_NombreToponimo.xml",
  &({String.to_integer(&1["_k_IdTipoToponimo"]), &1["_k_IdToponimo"]} in kept)
)

keep.("T10.X_TopoRelacion.xml", &(pair_key.(&1, "_k_IdToponimoHistorico") in kept))

IO.puts("wrote the place sample to #{out}: #{MapSet.size(kept)} records")
