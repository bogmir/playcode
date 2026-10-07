defmodule Playcode.CitationOracle do
  @moduledoc """
  Checks the renderer against FileMaker's own citations: for each record, and for each
  modern-edition link, the words FileMaker printed that ours lacks.

  Labels (`Vol.`, `Ed.`, `Tra.`…) and `{Falta …}` placeholders are left out, and letters
  are split from digits because FileMaker glues `London2010`. Neither order nor
  punctuation is compared: test/playcode/bibliography/citation_test.exs pins those.
  """

  alias Playcode.Bibliography.{Citation, Entry, Link}
  alias Playcode.Import.Bibliography

  @labels ~w(vol vols p pp ed eds tra url orig in i acc)

  @doc "`%{ref => [word]}` for every citation that lacks a word FileMaker printed."
  def misses(dir) do
    {:ok, data} = Bibliography.load(dir)
    lookups = Bibliography.lookups(data)
    editions = Bibliography.editions_by_id(data.editions)

    records =
      Enum.flat_map(data.bib_records, fn row ->
        attrs = Bibliography.record_attrs(row, lookups)
        theirs = row["_tc_BibSel_ComposicionExtensa"] || ""

        if theirs != "" and Entry.named?(attrs),
          do: [
            {"T12:" <> row["_kp_IdBiblioSelecta"], theirs, Citation.plain(struct(Entry, attrs))}
          ],
          else: []
      end)

    links =
      Enum.flat_map(data.edition_links, fn row ->
        theirs = row["w3pub_EdModernaItem"] || ""
        edition = editions[row["_k_IdEdicionModerna"]]

        if theirs != "" and edition do
          entry = struct(Entry, Bibliography.edition_attrs(edition, lookups))
          link = %Link{volume: row["ObraEdMod_Volumen"], pages: row["ObraEdMod_Paginas"]}

          [
            {"T04:#{row["_k_IdEdicionModerna"]} on #{row["_k_IdObraTitulo"]}", theirs,
             Citation.plain(entry, link)}
          ]
        else
          []
        end
      end)

    for {ref, theirs, ours} <- records ++ links,
        missing = MapSet.difference(words(theirs), words(ours)),
        MapSet.size(missing) > 0,
        into: %{} do
      {ref, missing |> MapSet.to_list() |> Enum.sort()}
    end
  end

  @doc "The words of a citation, as the oracle compares them."
  def words(text) do
    text
    |> String.replace(~r/\{Falta[^}]*\}/u, " ")
    |> String.replace(~r{</?(?:i|b|em)>}, " ")
    |> String.replace(["<<", ">>"], " ")
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> then(&Regex.scan(~r/[^\W\d_]+|\d+/u, &1))
    |> List.flatten()
    |> Enum.reject(&(&1 in @labels))
    |> MapSet.new()
  end
end
