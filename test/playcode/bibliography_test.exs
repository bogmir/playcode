defmodule Playcode.BibliographyTest do
  @moduledoc """
  The corpus-wide bibliography: entries shared by every play that cites them, read back
  through `Playcode.Bibliography`. Spec: docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Bibliography

  describe "entries and links" do
    test "an entry needs an author, an editor or a title" do
      play = play_fixture()

      assert {:error, changeset} =
               Bibliography.create_entry_for_play(play.id, %{
                 "kind" => "criticism",
                 "year_text" => "2005"
               })

      assert "needs an author, an editor or a title" in errors_on(changeset).monogr_title

      # Editions 273 and 420 in FileMaker have editors and no title, and are printed.
      assert {:ok, _} =
               Bibliography.create_entry_for_play(play.id, %{
                 "kind" => "modern_edition",
                 "monogr_editors" => "Herford, C. H."
               })
    end

    test "a title of spaces is no title" do
      play = play_fixture()

      assert {:error, changeset} =
               Bibliography.create_entry_for_play(play.id, %{
                 "kind" => "criticism",
                 "monogr_title" => "   "
               })

      assert "needs an author, an editor or a title" in errors_on(changeset).monogr_title
    end

    test "kind, type and language come from their lists" do
      play = play_fixture()

      {:error, changeset} =
        Bibliography.create_entry_for_play(play.id, %{
          "kind" => "review",
          "pub_type" => "poster",
          "language" => "xx",
          "monogr_title" => "T"
        })

      errors = errors_on(changeset)
      assert errors.kind == ["is invalid"]
      assert errors.pub_type == ["is invalid"]
      assert errors.language == ["is invalid"]
    end

    test "an edit to a shared entry shows on every play that has it" do
      hamlet = play_fixture()
      antony = play_fixture()
      link = bibliography_fixture(hamlet, %{"monogr_title" => "Complete Works"})
      {:ok, _} = Bibliography.link_entry(antony.id, link.entry_id)

      {:ok, _} =
        Bibliography.update_entry(Bibliography.get_entry!(link.entry_id), %{"year_text" => "1986"})

      for play <- [hamlet, antony] do
        assert [%{entry: %{year_text: "1986"}}] = Bibliography.list_links(play.id)
      end

      assert Enum.map(Bibliography.plays_for_entry(link.entry_id), & &1.code) ==
               Enum.sort([hamlet.code, antony.code])

      assert Bibliography.link_counts([link.entry_id]) == %{link.entry_id => 2}
    end

    test "the link holds what belongs to one play" do
      hamlet = play_fixture()
      antony = play_fixture()

      link =
        bibliography_fixture(hamlet, %{"kind" => "modern_edition", "monogr_title" => "Works"}, %{
          "volume" => "5",
          "pages" => "1-100"
        })

      {:ok, other} = Bibliography.link_entry(antony.id, link.entry_id, %{"volume" => "7"})
      {:ok, _} = Bibliography.update_link(other, %{"pages" => "200-300"})

      assert [%{volume: "5", pages: "1-100"}] = Bibliography.list_links(hamlet.id)
      assert [%{volume: "7", pages: "200-300"}] = Bibliography.list_links(antony.id)
    end

    test "a play links an entry only once" do
      play = play_fixture()
      link = bibliography_fixture(play)

      assert {:error, changeset} = Bibliography.link_entry(play.id, link.entry_id)
      assert "is already linked to this play" in errors_on(changeset).entry_id
    end

    test "removing an entry from its last play deletes it" do
      hamlet = play_fixture()
      antony = play_fixture()
      link = bibliography_fixture(hamlet, %{"monogr_title" => "Shared volume"})
      {:ok, other} = Bibliography.link_entry(antony.id, link.entry_id)

      assert {:ok, :unlinked} = Bibliography.unlink(link)

      assert Enum.map(Bibliography.search_entries("Shared volume", hamlet.id), & &1.id) ==
               [link.entry_id]

      assert {:ok, :deleted} = Bibliography.unlink(other)
      assert Bibliography.search_entries("Shared volume", hamlet.id) == []
    end
  end

  describe "an entry a performance cites" do
    defp found(term, play, opts \\ []),
      do: term |> Bibliography.search_entries(play.id, 10, opts) |> Enum.map(& &1.id)

    test "a catalogue is an entry the play's bibliography never shows or finds" do
      play = play_fixture()

      wiggins =
        catalogue_fixture(%{
          "monogr_author" => "Wiggins, Martin",
          "monogr_title" => "British Drama"
        })

      performance_fixture(play, %{"source_entry_id" => wiggins.id})

      assert Bibliography.list_for_play(play.id) == []
      assert found("Wiggins", play) == []
      assert found("Wiggins", play, kinds: :all) == [wiggins.id]
    end

    test "a search over every kind finds the play's own entries and the other plays' too" do
      play = play_fixture()
      own = bibliography_fixture(play, %{"monogr_title" => "Own Shakespeare"})

      other =
        bibliography_fixture(play_fixture(), %{
          "kind" => "modern_edition",
          "monogr_title" => "Other Shakespeare"
        })

      catalogue = catalogue_fixture(%{"monogr_title" => "Catalogue Shakespeare"})

      assert found("Shakespeare", play) == [other.entry_id]

      assert found("Shakespeare", play, kinds: :all) ==
               [catalogue.id, other.entry_id, own.entry_id]
    end

    test "an entry a performance cites outlives the play's last link to it" do
      hamlet = play_fixture()
      link = bibliography_fixture(hamlet, %{"monogr_title" => "Cited volume"})
      performance_fixture(play_fixture(), %{"source_entry_id" => link.entry_id})

      assert {:ok, :unlinked} = Bibliography.unlink(link)
      assert %{id: id} = Bibliography.get_entry(link.entry_id)
      assert id == link.entry_id
    end

    test "the plays an entry is shared with include those whose performances cite it" do
      hamlet = play_fixture()
      antony = play_fixture()
      link = bibliography_fixture(hamlet, %{"monogr_title" => "Cited volume"})
      id = link.entry_id

      # A play counts once, however many performances cite the entry, and once more
      # for linking it as well.
      performance_fixture(hamlet, %{"source_entry_id" => id})
      performance_fixture(antony, %{"source_entry_id" => id})
      performance_fixture(antony, %{"source_entry_id" => id, "date_text" => "1611"})

      assert Enum.map(Bibliography.plays_for_entry(id), & &1.code) ==
               Enum.sort([hamlet.code, antony.code])

      assert Bibliography.link_counts([id]) == %{id => 2}
    end

    test "a catalogue is shared by the plays whose performances cite it" do
      catalogue = catalogue_fixture()
      plays = [play_fixture(), play_fixture(), play_fixture()]
      for play <- plays, do: performance_fixture(play, %{"source_entry_id" => catalogue.id})

      assert Enum.map(Bibliography.plays_for_entry(catalogue.id), & &1.code) ==
               plays |> Enum.map(& &1.code) |> Enum.sort()

      assert Bibliography.link_counts([catalogue.id, Ecto.UUID.generate()]) ==
               %{catalogue.id => 3}
    end

    test "get_entry/1 is nil for a malformed or missing id" do
      entry = catalogue_fixture()

      assert Bibliography.get_entry(entry.id).id == entry.id
      assert Bibliography.get_entry("no-uuid") == nil
      assert Bibliography.get_entry(Ecto.UUID.generate()) == nil
      assert Bibliography.get_entry(nil) == nil
    end

    test "delete_if_unused/1 deletes an entry nothing cites, and keeps one a link or a performance does" do
      play = play_fixture()
      linked = bibliography_fixture(play)
      cited = catalogue_fixture()
      performance_fixture(play, %{"source_entry_id" => cited.id})
      unused = catalogue_fixture()

      assert Bibliography.delete_if_unused(linked.entry_id) == :kept
      assert Bibliography.delete_if_unused(cited.id) == :kept
      assert Bibliography.delete_if_unused(unused.id) == :deleted
      assert Bibliography.get_entry(unused.id) == nil
      assert Bibliography.get_entry(linked.entry_id)
      assert Bibliography.get_entry(cited.id)
    end
  end

  describe "search_entries/3" do
    test "finds entries by author, editor or title, leaving out the play's own" do
      hamlet = play_fixture()
      antony = play_fixture()
      bibliography_fixture(hamlet, %{"monogr_title" => "Shakespeare Survey"})

      other =
        bibliography_fixture(antony, %{
          "monogr_title" => "The Riverside Shakespeare",
          "monogr_editors" => "Evans, G. Blakemore"
        })

      assert Enum.map(Bibliography.search_entries("shakespeare", hamlet.id), & &1.id) ==
               [other.entry_id]

      assert Enum.map(Bibliography.search_entries("evans", hamlet.id), & &1.id) ==
               [other.entry_id]
    end

    test "% and _ match themselves, and a blank term finds nothing" do
      play = play_fixture()
      wanted = bibliography_fixture(play_fixture(), %{"monogr_title" => "100% Shakespeare"})
      bibliography_fixture(play_fixture(), %{"monogr_title" => "1000 Plays"})

      assert Enum.map(Bibliography.search_entries("100%", play.id), & &1.id) ==
               [wanted.entry_id]

      assert Bibliography.search_entries("", play.id) == []
      assert Bibliography.search_entries("  ", play.id) == []
      assert Bibliography.search_entries("%", play.id) == []
    end
  end

  describe "list_for_play/1" do
    test "groups by kind in display order, leaving out empty kinds" do
      play = play_fixture()
      bibliography_fixture(play, %{"kind" => "adaptation", "monogr_title" => "Adapted"})
      bibliography_fixture(play, %{"kind" => "criticism", "monogr_title" => "Studied"})
      bibliography_fixture(play, %{"kind" => "modern_edition", "monogr_title" => "Edited"})

      assert Enum.map(Bibliography.list_for_play(play.id), &elem(&1, 0)) ==
               ~w(modern_edition criticism adaptation)
    end

    test "sorts by the first name printed, ignoring case, accents and opening quotes" do
      play = play_fixture()

      for {author, title} <- [
            {"Zúñiga, Ana", "Z"},
            {nil, ~s("Ópera" y teatro)},
            {"álvarez, Luis", "A"},
            {"Barnett, Tim", "B"}
          ] do
        bibliography_fixture(play, %{"monogr_author" => author, "monogr_title" => title})
      end

      assert [{"criticism", [{nil, links}]}] = Bibliography.list_for_play(play.id)

      assert Enum.map(links, & &1.entry.monogr_author) ==
               ["álvarez, Luis", "Barnett, Tim", nil, "Zúñiga, Ana"]
    end

    test "translations are subgrouped by language, unknown last" do
      play = play_fixture()

      for {language, title} <- [
            {nil, "Sin idioma"},
            {"fr", "Traduction"},
            {"es", "Traducción"},
            {"en", "Translation"}
          ] do
        bibliography_fixture(play, %{
          "kind" => "translation",
          "language" => language,
          "monogr_title" => title
        })
      end

      assert [{"translation", groups}] = Bibliography.list_for_play(play.id)
      assert Enum.map(groups, &elem(&1, 0)) == ["es", "en", "fr", nil]
    end
  end
end
