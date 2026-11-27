defmodule Playcode.Import.WordDraftTest do
  @moduledoc """
  The draft of a premarked text, `WordParser.draft/2`: the play as the Word import would
  store it, built in memory for the premarked page's preview. The import inserts exactly
  these rows, so the draft is compared with what the import then stored.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.{Catalogue, Outline, PlayContent}
  alias Playcode.Catalogue.Paratext
  alias Playcode.Import.WordParser

  @ejercicio "test/fixtures/word_files/ejercicio.docx"
  @bartholomew "test/fixtures/word_files/bartholomew_fair.docx"

  defp play_with_paratexts(play), do: Catalogue.get_play_with_all!(play.id)

  defp file_paragraphs(path) do
    {:ok, paragraphs} = WordParser.paragraphs(path)
    paragraphs
  end

  defp draft!(paragraphs, play) do
    assert {:ok, draft} = WordParser.draft(paragraphs, play_with_paratexts(play))
    draft
  end

  defp assert_draft_is_stored(paragraphs) do
    play = play_fixture()
    draft = draft!(paragraphs, play)
    assert {:ok, _} = WordParser.import_content(play.id, paragraphs)

    assert_same(rows(draft.divisions), rows(PlayContent.load_play_content(play.id)))
    assert outline(draft.paratexts, draft.divisions) == stored_outline(play)
    draft
  end

  # Row by row, so that a long play's difference prints as its first differing row.
  defp assert_same(drafted, stored) do
    mismatch = drafted |> Enum.zip(stored) |> Enum.find(fn {a, b} -> a != b end)
    if mismatch, do: assert(elem(mismatch, 0) == elem(mismatch, 1))
    assert length(drafted) == length(stored)
  end

  defp rows(divisions) do
    Enum.flat_map(divisions, fn division ->
      {type, title, number, position, entries, _children, _elements} = division(division)

      [{type, title, number, position, entries}] ++
        Enum.flat_map(division.loaded_elements, &element_rows/1) ++
        rows(children(division))
    end)
  end

  defp element_rows(element) do
    {type, content, n, part, label, aside, continues, position, speakers, _children} =
      element(element)

    [{type, content, n, part, label, aside, continues, position, speakers}] ++
      Enum.flat_map(element.children, &element_rows/1)
  end

  defp tree(divisions), do: Enum.map(divisions, &division/1)

  defp division(division) do
    {division.type, division.title, division.number, division.position, entries(division),
     tree(children(division)), Enum.map(division.loaded_elements, &element/1)}
  end

  defp children(%{children: children}) when is_list(children), do: children
  defp children(_division), do: []

  defp entries(%{entries: entries}) when is_list(entries),
    do: Enum.map(entries, &{&1.name, &1.position, &1.character.xml_id, &1.character.name})

  defp entries(_division), do: []

  defp element(element) do
    {element.type, element.content, element.line_number, element.part, element.speaker_label,
     element.is_aside, element.aside_continues, element.position,
     Enum.map(element.element_characters, & &1.character.name),
     Enum.map(element.children, &element/1)}
  end

  # Items at one position fall in id order, and the draft's ids are not the stored ones.
  defp outline(paratexts, divisions) do
    paratexts
    |> Outline.items(divisions)
    |> Enum.map(fn
      %Paratext{} = p -> {p.position, :paratext, p.kind, p.heading, p.content, p.origin}
      division -> {division.position, :division, division.type, division.title}
    end)
    |> Enum.sort()
  end

  defp stored_outline(play) do
    play = play_with_paratexts(play)
    outline(play.paratexts, PlayContent.load_play_content(play.id))
  end

  describe "the draft is what the import stores" do
    test "for the exercise" do
      assert_draft_is_stored(file_paragraphs(@ejercicio))
    end

    test "for Bartholomew Fair, prologue, induction and all" do
      assert_draft_is_stored(file_paragraphs(@bartholomew))
    end

    test "for speeches with no act or scene before them" do
      draft = assert_draft_is_stored(["{p}FEBO {v}Uno.", "{p}RICARDO {v}Dos."])
      assert [_cast_list, _act] = draft.divisions
    end

    test "for a prologue holding a stanza, then an act" do
      assert_draft_is_stored([
        "PROLOGUE",
        "{p}PROLOGUE {m} {v}First line,",
        "{v}second line.",
        "ACTO PRIMERO",
        "{e}Escena 1",
        "{p}FEBO {pr}Prosa.",
        "{p}RICARDO {ap}(Aparte) {v}Un aparte."
      ])
    end

    test "numbered by the play's own rule" do
      play = play_fixture()

      {:ok, play} =
        Catalogue.update_play(play, %{numbering_type: "VP", numbering_restart: "scene"})

      paragraphs = [
        "{e}Escena 1",
        "{p}FEBO {v}Uno.",
        "{pr}Prosa.",
        "{e}Escena 2",
        "{p}RICARDO {v}Dos."
      ]

      draft = draft!(paragraphs, play)
      assert {:ok, _} = WordParser.import_content(play.id, paragraphs)

      assert tree(draft.divisions) == tree(PlayContent.load_play_content(play.id))
    end
  end

  test "a re-import keeps the paratexts typed by hand, and the draft prints them" do
    play = play_fixture()

    assert {:ok, _} =
             WordParser.import_content(play.id, [
               "Old front matter.",
               "{e}Escena 1",
               "{p}FEBO {v}Uno."
             ])

    {:ok, manual} =
      Catalogue.create_paratext(%{
        play_id: play.id,
        kind: "dedicatoria",
        heading: "Dedicatoria",
        content: "Al lector.",
        position: 5,
        origin: "manual"
      })

    paragraphs = ["New front matter.", "{e}Escena 1", "{p}FEBO {v}Dos."]
    draft = draft!(paragraphs, play)

    contents = Enum.map(draft.paratexts, & &1.content)
    assert "New front matter." in contents
    assert "Al lector." in contents
    refute "Old front matter." in contents
    assert manual in draft.paratexts

    assert {:ok, _} = WordParser.import_content(play.id, paragraphs)
    assert outline(draft.paratexts, draft.divisions) == stored_outline(play)
  end

  test "the summary counts acts, scenes, verses and each speaker's speeches" do
    play = play_fixture()
    paragraphs = file_paragraphs(@ejercicio)
    draft = draft!(paragraphs, play)
    assert {:ok, _} = WordParser.import_content(play.id, paragraphs)

    assert %{acts: 1, scenes: 1} = draft.summary
    assert draft.summary.verses == Catalogue.get_play!(play.id).verse_count
    assert [{"RICARDO", ricardo} | _] = draft.summary.speakers
    assert ricardo > 1
  end

  test "every row knows the paragraph it came from" do
    play = play_fixture()
    draft = draft!(["{e}Escena 1", "", "{p}FEBO {v}Uno.", "{v}Dos."], play)

    [_cast_list, act] = draft.divisions
    [scene] = act.children
    [speech] = scene.loaded_elements
    [uno, dos] = speech.children

    assert draft.lines[scene.id] == 0
    assert draft.lines[speech.id] == 2
    assert draft.lines[uno.id] == 2
    assert draft.lines[dos.id] == 3
  end

  describe "warnings" do
    defp warnings(paragraphs) do
      draft = draft!(paragraphs, play_fixture())
      Enum.map(draft.warnings, &{&1.line, &1.kind})
    end

    test "an untagged paragraph after the text starts" do
      assert warnings(["{e}Escena 1", "{p}FEBO {v}Uno.", "OBSERVACIONES:"]) == [{2, :untagged}]
    end

    test "a tag the parser does not know, left as typed" do
      assert warnings(["{e}Escena 1", "{R}Vase."]) == [{1, :unknown_tag}]
    end

    test "text before the paragraph's first tag" do
      assert warnings(["{e}Escena 1", "Nota {p}FEBO {v}Uno."]) == [{1, :dropped_text}]
    end

    test "a middle or final part with no initial part open" do
      assert warnings(["{e}Escena 1", "{p}FEBO {v}Uno.", "{p}RICARDO {tf}¿No lo ves?"]) ==
               [{2, :part_without_initial}]
    end

    test "an initial part no final part closes" do
      assert warnings(["{e}Escena 1", "{p}FEBO {ti}¿Cantan?", "{p}RICARDO {v}Dos."]) ==
               [{1, :initial_unfinished}]

      assert warnings(["{e}Escena 1", "{p}FEBO {v}Uno.", "{ti}pues ¿qué te aflige?"]) ==
               [{2, :initial_unfinished}]
    end

    test "a speaker's name tagged as words" do
      assert warnings(["{e}Escena 1", "{p}FEBO {v}Uno.", "{pr} FEBO {pr}¡Qué pronto!"]) ==
               [{2, :speaker_as_words}]
    end

    test "an end marker, kept as an unrecognised line" do
      assert warnings(["{e}Escena 1", "{p}FEBO {v}Uno.", "{e}THE END"]) == [{2, :end_marker}]
    end

    test "an aside opened and never closed" do
      assert warnings(["{e}Escena 1", "{p}FEBO {pr}Hola ((aparte sin cerrar"]) ==
               [{1, :unclosed_aside}]
    end

    test "each warning keeps the text it is about" do
      draft = draft!(["{e}Escena 1", "{R}Vase."], play_fixture())
      assert [%{text: "{R}Vase."}] = draft.warnings
    end

    test "the exercise has none" do
      assert warnings(file_paragraphs(@ejercicio)) == []
    end

    # The fixture stops before the exercise's closing notes; these are its lines.
    test "the exercise's closing notes are untagged lines" do
      notes = [
        "OBSERVACIONES: ",
        "No se marca \"JORNADA I\" o \"ACTO I\".",
        "No hay que dejar líneas en blanco. ",
        "Acotación \"Vase\" al final de una línea se reubica en una nueva línea separada.",
        "Acotación dentro de un parlamento: se reubica en una nueva línea, y se marca también el texto del diálogo que sigue a la acotación"
      ]

      paragraphs = file_paragraphs(@ejercicio) ++ ["", ""] ++ notes
      first = length(paragraphs) - 5

      assert warnings(paragraphs) == for(line <- first..(first + 4), do: {line, :untagged})
    end

    test "Bartholomew Fair: its names tagged as prose, its untagged paragraphs and its {R}" do
      counts =
        @bartholomew |> file_paragraphs() |> warnings() |> Enum.frequencies_by(&elem(&1, 1))

      # The brief counted 30 names and 32 untagged paragraphs by eye: the 38 lines of the cast
      # list and 31 prose lines carried over untagged are stored unrecognised too, and of the
      # names it counted, CORN-CUTTER never speaks, so it is not a speaker's name.
      assert %{speaker_as_words: 28, untagged: 69, unknown_tag: 1} =
               Map.take(counts, [:speaker_as_words, :untagged, :unknown_tag])
    end
  end
end
