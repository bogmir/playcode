defmodule Playcode.ContentVersionTest do
  @moduledoc """
  `plays.content_version`, which Postgres moves whenever something a play's static pages
  show changes, so the export can tell which published plays are out of date. Every edit
  goes through a context; the version is read back with `Catalogue.get_play!/2`.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.{Catalogue, PlayContent, Places, Statistics}

  # Postgres moves a play once per transaction, and the sandbox runs the whole test in
  # one. This stands in for the commit between two edits. It reaches past the contexts
  # because nothing outside the database can end a transaction inside the sandbox.
  defp next_transaction do
    Playcode.Repo.query!(
      "UPDATE plays SET content_txid = NULL WHERE content_txid = txid_current()"
    )
  end

  defp version(play), do: Catalogue.get_play!(play.id, include_deleted: true).content_version

  # Whether `edit`, run as a transaction of its own, moves `play`'s version.
  defp moves?(play, edit) do
    next_transaction()
    before = version(play)
    edit.()
    version(play) > before
  end

  test "a new play has a version" do
    assert is_integer(play_fixture().content_version)
  end

  test "every edit to the text, cast, credits, notes or places moves the play" do
    %{play: play, character: character, act: act, speech: speech, verse_line: line} =
      play_with_structure_fixture()

    place = place_fixture()

    edits = [
      division: fn -> PlayContent.update_division(act, %{title: "ACTO I"}) end,
      element: fn -> PlayContent.update_element(line, %{content: "Otro verso"}) end,
      character: fn -> PlayContent.update_character(character, %{name: "BETA"}) end,
      speaker: fn -> PlayContent.set_element_characters(speech.id, []) end,
      editor: fn ->
        Catalogue.create_play_editor(%{
          play_id: play.id,
          person_name: "Ed",
          role: "editor",
          position: 1
        })
      end,
      source: fn ->
        Catalogue.create_play_source(%{play_id: play.id, title: "Fuente", position: 1})
      end,
      note: fn ->
        Catalogue.create_play_editorial_note(%{
          play_id: play.id,
          section_type: "nota",
          content: "Nota",
          position: 1
        })
      end,
      place: fn -> play_place_fixture(play, place) end,
      deletion: fn -> PlayContent.delete_element(line) end
    ]

    for {what, edit} <- edits do
      assert moves?(play, edit), "#{what} did not move the play's version"
    end
  end

  test "several edits in one transaction move the play once" do
    %{play: play, act: act, scene: scene} = play_with_structure_fixture()

    next_transaction()
    {:ok, _} = PlayContent.update_division(act, %{title: "ACTO I"})
    once = version(play)
    {:ok, _} = PlayContent.update_division(scene, %{title: "ESCENA I"})

    assert version(play) == once
  end

  test "a change to a play's own fields moves it, its original and its translations" do
    %{original: original, translation: translation} = translation_family_fixture()
    unrelated = play_fixture()
    plays = [original, translation, unrelated]

    next_transaction()
    before = Enum.map(plays, &version/1)
    {:ok, _} = Catalogue.update_play(original, %{"title" => "Nuevo título"})

    assert Enum.zip_with(plays, before, &(version(&1) > &2)) == [true, true, false]
  end

  # The other way round: the original's title page lists its translations.
  test "a change to a translation's own fields moves its original" do
    %{original: original, translation: translation} = translation_family_fixture()
    unrelated = play_fixture()
    plays = [original, translation, unrelated]

    next_transaction()
    before = Enum.map(plays, &version/1)
    {:ok, _} = Catalogue.update_play(translation, %{"title" => "New title"})

    assert Enum.zip_with(plays, before, &(version(&1) > &2)) == [true, true, false]
  end

  # Only a play's own row shows on its relatives' title pages.
  test "an edit to a play's text moves that play and no other" do
    %{original: original, translation: translation} = translation_family_fixture()

    next_transaction()
    {original_before, translation_before} = {version(original), version(translation)}

    {:ok, _} =
      PlayContent.create_division(%{
        play_id: translation.id,
        type: "acto",
        number: 1,
        position: 1
      })

    assert version(translation) > translation_before
    assert version(original) == original_before
  end

  test "an edit to a place moves every play set there or anywhere inside it" do
    country = place_fixture(%{"type" => "country"})
    city = place_fixture(%{"parent_place_id" => country.id})
    play = play_fixture()
    play_place_fixture(play, city)
    elsewhere = play_fixture()
    play_place_fixture(elsewhere, place_fixture())

    note = fn -> Places.update_place(Places.get_place!(country.id), %{"note" => "Reino"}) end

    # The slug is passed so that only the name changes, not the places row.
    rename = fn ->
      reloaded = Places.get_place!(country.id)
      [name] = reloaded.names

      Places.update_place(reloaded, %{
        "slug" => reloaded.slug,
        "names" => [%{"id" => name.id, "name" => "Hispania"}]
      })
    end

    assert moves?(play, note)
    assert moves?(play, rename)
    refute moves?(elsewhere, note)
  end

  test "caching a play's statistics does not move it" do
    %{play: play} = play_with_structure_fixture()
    refute moves?(play, fn -> Statistics.recompute(play.id) end)
  end

  # A new table whose rows appear on a play's pages needs the trigger, one line in its
  # migration (see the moduledoc of
  # priv/repo/migrations/20261005120000_track_play_content_version.exs).
  test "every table with a play_id has the content trigger, or is not page data" do
    # Statistics are derived from the text and written by the export itself; the
    # activity log is an audit trail.
    not_page_data = ~w(play_statistics activity_logs)

    # Reads the schema itself: no context describes triggers.
    %{rows: rows} =
      Playcode.Repo.query!("""
      SELECT c.table_name,
             (SELECT count(DISTINCT t.event_manipulation)
                FROM information_schema.triggers t
               WHERE t.event_object_schema = c.table_schema
                 AND t.event_object_table = c.table_name
                 AND t.action_statement = 'EXECUTE FUNCTION play_row_changed()') = 3
        FROM information_schema.columns c
       WHERE c.table_schema = 'public' AND c.column_name = 'play_id'
      """)

    untracked = for [table, false] <- rows, table not in not_page_data, do: table
    assert untracked == []
  end
end
