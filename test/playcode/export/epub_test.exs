defmodule Playcode.Export.EpubTest do
  @moduledoc "The EPUB the preview downloads and the static site publishes."
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Catalogue
  alias Playcode.Export.Epub

  defp text_play(attrs \\ %{}) do
    {:ok, play} = Catalogue.update_play(play_with_structure_fixture().play, attrs)
    Catalogue.get_play_with_all!(play.id)
  end

  # A play whose pages last changed years ago, so its times cannot pass for the clock's or
  # its row's. Only Postgres writes that time, so this reaches the table.
  defp old_play do
    play = play_with_structure_fixture().play

    Playcode.Repo.query!(
      "UPDATE plays SET content_changed_at = '2020-03-04 05:06:07' WHERE id = $1",
      [Ecto.UUID.dump!(play.id)]
    )

    Catalogue.get_play_with_all!(play.id)
  end

  defp entries(epub) do
    {:ok, table} = :zip.table(epub)

    for {:zip_file, name, info, _comment, _offset, _size} <- table,
        do: {to_string(name), elem(info, 5)}
  end

  defp unzip(epub) do
    {:ok, files} = :zip.unzip(epub, [:memory])
    Enum.map(files, fn {name, body} -> {to_string(name), body} end)
  end

  test "an EPUB's times are its play's, not the clock's" do
    {:ok, epub} = Epub.generate(old_play())

    # A zip entry keeps its time to two seconds: 07 reads back as 06.
    assert epub |> entries() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() == [
             {{2020, 3, 4}, {5, 6, 6}}
           ]

    opf =
      Enum.find_value(unzip(epub), fn {name, body} -> String.ends_with?(name, ".opf") && body end)

    assert opf =~ ~s(<meta property="dcterms:modified">2020-03-04T05:06:07Z</meta>)
  end

  test "the same play gives the same bytes" do
    play = old_play()
    assert Epub.generate(play) == Epub.generate(play)
  end

  test "the archive opens with its mimetype, stored as it is" do
    {:ok, epub} = Epub.generate(text_play())

    assert [{"mimetype", _} | _] = entries(epub)
    # The first local header's name, then its body uncompressed.
    assert binary_part(epub, 30, 8) == "mimetype"
    assert binary_part(epub, 38, 20) == "application/epub+zip"
  end

  test "a title with italics and an author with an ampersand build a book whose chapters parse" do
    play = text_play(%{"title" => "La <<Celestina>>", "author_name" => "Beaumont & Fletcher"})
    {:ok, epub} = Epub.generate(play)

    for {name, body} <- unzip(epub), String.ends_with?(name, [".xhtml", ".opf", ".ncx"]) do
      assert {:ok, _} = Saxy.SimpleForm.parse_string(body), name
    end
  end
end
