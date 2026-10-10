# Rebuilds the witness sample in this directory from the git-ignored FileMaker dump: the
# T03 records below and the T03.2 attributions they name. Rows are copied byte for byte, so
# FileMaker's own rendering (w3_ObrTes_Composicion) comes with them. Run from the
# repository root:
#
#     mix run --no-start test/fixtures/filemaker/witnesses/regenerate.exs
#
# One record per rule: every type, Jodelle's name dropped from a Spanish play (77, 79) and
# kept on his own (92), sigla that are no XML name (142, 143), no title (140), the test
# record (32), an empty one (15), a version no play holds (95). See "Testing" in
# docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

alias Playcode.Import.FilemakerXml

dump = "doc/ctce_dades"
out = Path.dirname(__ENV__.file)

records = ~w(15 32 33 36 77 79 92 95 140 142 143 240 267 268 269 499)

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

keep.("T03_ObraTestimonio.xml", "_kp_IdObraTestimonio", MapSet.new(records))
{:ok, kept} = FilemakerXml.read(Path.join(out, "T03_ObraTestimonio.xml"))
keep.("T03.2_Atribucion.xml", "_kp_IdAtribucion", MapSet.new(kept, & &1["_k_IdAtribucion"]))

IO.puts("wrote the witness sample to #{out}")
