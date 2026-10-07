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
end
