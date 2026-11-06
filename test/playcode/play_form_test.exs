defmodule Playcode.PlayFormTest do
  @moduledoc """
  A play's form, verse, prose or both (questions 22 and 23). Worked out from the share of
  its text in verse, by length, every verse line counted whether numbered or not: none is
  prose, under a tenth prose with occasional verse, more is verse. "Verse and prose" is
  only ever a researcher's choice, in the play's form, which wins over the rule.

  The file labels the form on `extent`, as the EMOTHE files do (`ana="verso"`); a form a
  researcher chose carries `resp="#equipo"` there and comes back from the file. The old
  files' labels carry no mark and are not read: they proved wrong both ways (Hamlet,
  65% verse, `verso`; Castro, all verse, `versoprosa`).
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play

  defp paragraphs(n),
    do: Enum.map_join(1..n, &"<p>#{String.duplicate("Palabras de la prosa ", 10)}#{&1}</p>")

  defp verses(n, opts \\ []) do
    Enum.map_join(1..n, fn i ->
      number = if Keyword.get(opts, :numbered, true), do: ~s( n="#{i}")
      ~s(<l#{number}>Verso de la comedia número #{i}</l>)
    end)
  end

  defp import_play(speech, opts \\ []) do
    body = ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker>#{speech}</sp></div1>)
    opts |> Keyword.put(:body, body) |> tei() |> import_tei!()
  end

  defp form(play), do: play.id |> Catalogue.get_play!() |> Play.form()

  # The file's own label of the form: `{ana, resp, text}` of `fileDesc/extent`.
  defp label(play) do
    {attrs, text} = play |> export_tei() |> xml_elements("extent", within: "fileDesc") |> hd()
    attrs = Map.new(attrs)
    {attrs["ana"], attrs["resp"], text}
  end

  describe "the form worked out from the text" do
    test "no verse is prose" do
      assert import_play(paragraphs(20)) |> form() == "prose"
    end

    test "under a tenth of the text in verse is prose with occasional verse" do
      assert import_play(paragraphs(20) <> verses(2)) |> form() == "occasional_verse"
    end

    test "more is verse, its verse lines counted whether numbered or not" do
      assert import_play(paragraphs(2) <> verses(30)) |> form() == "verse"
      assert import_play(verses(30, numbered: false)) |> form() == "verse"
    end

    test "an old file's label is not read as a researcher's choice" do
      play = import_play(verses(30), file_desc: ~s(<extent ana="versoprosa">30</extent>))

      assert form(play) == "verse"
      assert Catalogue.get_play!(play.id).form == nil
    end
  end

  describe "the form in the file" do
    test "the file labels the form worked out, with the verse count, unmarked" do
      assert label(import_play(verses(30))) == {"verso", nil, "30 versos"}
      assert label(import_play(paragraphs(20) <> verses(2))) == {"prosaverso", nil, "2 versos"}
    end

    test "a prose play is labelled prose, with no count of verses" do
      assert label(import_play(paragraphs(20))) == {"prosa", nil, ""}
    end

    test "a form a researcher chose is marked, and comes back from the file" do
      play = import_play(verses(30))
      {:ok, play} = Catalogue.update_play(play, %{"form" => "mixed"})

      assert label(play) == {"versoprosa", "#equipo", "30 versos"}

      xml = String.replace(export_tei(play), play.code, "#{play.code}B")
      imported = import_tei!(xml)

      assert Catalogue.get_play!(imported.id).form == "mixed"
    end
  end
end
