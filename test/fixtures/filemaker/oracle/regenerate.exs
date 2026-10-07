# Rebuilds the oracle sample in this directory from the git-ignored FileMaker dump: the
# records and modern-edition links below, the links of those records, and the cities and
# publishers they name. Rows are copied byte for byte, so FileMaker's own citation text
# comes with them. Run from the repository root:
#
#     mix run --no-start test/fixtures/filemaker/oracle/regenerate.exs
#
# The ids cover every publication type and every optional field. See "Testing" in
# docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

alias Playcode.Import.FilemakerXml

dump = "doc/ctce_dades"
out = Path.dirname(__ENV__.file)

records =
  ~w(36 40 37 38 1417 1751 43 49 61 62 1024 1435 70 133 84 86 107 115 184 187 193 674 675 113 1420 331 516 94 111 1405)

edition_links = ~w(40 42 26 44 59 65 60 61 52 58 55 957 54 79 69 757)

# Keeps the rows of `file` whose `field` is in `keep`, and rewrites FOUND to match.
keep = fn file, field, keep ->
  xml = File.read!(Path.join(dump, file))

  names =
    ~r/<FIELD [^>]*NAME="([^"]+)"/ |> Regex.scan(xml, capture: :all_but_first) |> List.flatten()

  index = Enum.find_index(names, &(&1 == field))
  [head, rest] = String.split(xml, "<RESULTSET", parts: 2)
  [_found, rows] = String.split(rest, ">", parts: 2)

  kept =
    ~r{<ROW [^>]*>.*?</ROW>}s
    |> Regex.scan(rows)
    |> List.flatten()
    |> Enum.filter(fn row ->
      cols = ~r{<COL>(.*?)</COL>}s |> Regex.scan(row, capture: :all_but_first) |> List.flatten()
      value = cols |> Enum.at(index, "") |> String.replace(~r{</?DATA>}, "")
      MapSet.member?(keep, value)
    end)

  File.write!(
    Path.join(out, file),
    head <>
      ~s(<RESULTSET FOUND="#{length(kept)}">) <> Enum.join(kept) <> "</RESULTSET></FMPXMLRESULT>"
  )
end

{:ok, all_links} = FilemakerXml.read(Path.join(dump, "T04_ObraModernaRecomendada.xml"))

editions =
  all_links
  |> Enum.filter(&(&1["_kp_IdObraEdModRecomendada"] in edition_links))
  |> MapSet.new(& &1["_k_IdEdicionModerna"])

keep.("T12.1_BibliografiaSelecta.xml", "_kp_IdBiblioSelecta", MapSet.new(records))
keep.("T12_ObraBibliografiaSelecta.xml", "_k_IdBiblioSelecta", MapSet.new(records))
keep.("T04_ObraModernaRecomendada.xml", "_kp_IdObraEdModRecomendada", MapSet.new(edition_links))
keep.("T04.1_EdModerna.xml", "_kp_IdEdicionModerna", editions)

{:ok, kept_records} = FilemakerXml.read(Path.join(out, "T12.1_BibliografiaSelecta.xml"))
{:ok, kept_editions} = FilemakerXml.read(Path.join(out, "T04.1_EdModerna.xml"))
named = fn field -> MapSet.new(kept_records ++ kept_editions, & &1[field]) end

keep.("T13.1_Ciudad.xml", "_kp_IdCiudad", named.("_k_IdCiudad"))
keep.("T13.2_Editorial.xml", "_kp_IdEditorial", named.("_k_IdEditorial"))

IO.puts("wrote the oracle sample to #{out}")
