defmodule Playcode.CompleteCopyTest do
  @moduledoc """
  The TEI file is a complete copy of a play (`CLAUDE.md`): a play with every part filled
  in, exported and imported into an empty Playcode, comes back whole.

  The fixpoint tests in `tei_roundtrip_test.exs` compare the XML with itself, so a column
  the export never writes passes them. This one compares the play: it is read back
  through the contexts' public functions, every column of every row but those in
  `@dropped`, so a new column joins the comparison without anyone adding it. That reaches
  past what a TEI consumer observes, on purpose: an export cannot show what it leaves out.

  A new column is written to the file, dropped below with the reason, or listed in
  `known_gaps/0` with the item of `docs/backlog.md` that will close it.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.TestFixtures, only: [play_fixture: 1, place_fixture: 1]

  alias Playcode.Bibliography
  alias Playcode.Catalogue
  alias Playcode.Places
  alias Playcode.PlayContent

  # How rows are stored, not what they hold: identifiers and links (a row's place in the
  # tree is its place in the snapshot), order (the lists are in order), provenance and
  # timestamps. Then what stays out of the file on purpose (CLAUDE.md, *The TEI file is a
  # complete copy of a play*): whether the play is complete, and whether its variants are
  # shown, the two switches for what readers see.
  @dropped ~w(id play_id parent_id division_id element_id entry_id place_id parent_place_id
              parent_play_id position origin filemaker_id inserted_at updated_at
              content_version deleted_at pending_original_code is_complete show_variants)a

  # The researchers' private notes, never written to the file: it is published with the
  # site. Dropped by schema, not by name: every other `note` is the play's.
  @private %{Bibliography.Entry => [:note], Bibliography.Link => [:note]}

  test "a play with every part filled in comes back whole from its TEI file" do
    original = play_fixture(%{"code" => "CCO#{System.unique_integer([:positive])}"})

    # Built in a transaction rolled back, so the import meets an empty Playcode. The
    # bibliography and the places are shared by the corpus: purging only the play would
    # leave them for the import to link to instead of reading them from the file. Repo is
    # reached for directly because no context opens a transaction for a caller.
    {:error, {built, xml}} =
      Playcode.Repo.transaction(fn ->
        play = build_play(original)
        Playcode.Repo.rollback({snapshot(play.id), export_tei(play)})
      end)

    assert Places.list_places() == []

    imported = import_tei!(xml)

    expected =
      Enum.reduce(known_gaps(), built, fn {_item, path, lose}, snapshot ->
        update_in(snapshot, Enum.map(path, &step/1), lose)
      end)

    assert differences(expected, snapshot(imported.id)) == []
  end

  # A list index in a known gap's path; at!/1 raises on an index that is gone, so a gap
  # whose row has moved fails instead of patching nothing.
  defp step(index) when is_integer(index), do: Access.at!(index)
  defp step(key), do: key

  # What the round trip loses today: {the item of docs/backlog.md that closes it, the
  # path in the snapshot, what the round trip makes of the value there}. Closing a gap
  # turns the test red until its entry goes.
  defp known_gaps do
    [
      {"Verse, prose or mixed", [:play, :form], fn _form -> nil end},
      # The credits come back in the order of the file's sections: the principal
      # investigator, the title statement's editors, then the statements of responsibility.
      {"The order of the credits", [:editors],
       &Enum.sort_by(&1, fn %{role: role} -> credit_section(role) end)},
      {"Italics before punctuation gain a space", [:paratexts, 0, :content],
       &String.replace(&1, ">>,", ">> ,")}
      # "A second cast list": Playcode cannot hold one yet, so this play has none to lose.
    ]
  end

  defp credit_section("principal"), do: 0
  defp credit_section(role) when role in ~w(translator researcher critical_editor), do: 1
  defp credit_section(_role), do: 2

  # --- The play ---

  # Every part of a play that the file carries (docs/stakeholder/ida-y-vuelta.html), each
  # column off its default, built through the contexts as the admin pages build it.
  defp build_play(original) do
    {:ok, play} =
      Catalogue.create_play(%{
        title: "La comedia completa",
        title_sort: "comedia completa",
        code: "CC#{System.unique_integer([:positive])}",
        language: "it",
        author_name: "Autora, Ana",
        author_sort: "Autora",
        author_attribution: "fiable",
        publication_date: "2026",
        form: "mixed",
        publisher: "ARTELOPE/EMOTHE",
        pub_place: "Valencia",
        availability_note: "Uso libre.",
        project_description: "El proyecto.",
        editorial_declaration: "Los criterios.",
        original_title: "The Complete Comedy",
        licence_url: "https://creativecommons.org/licenses/by-nc-nd/4.0/",
        licence_text: "CC BY-NC-ND 4.0",
        emothe_id: "0999",
        sponsor: "Plan Nacional",
        funder: "Ministerio",
        authority: "Universitat de València",
        parent_play_id: original.id,
        relationship_type: "traduccion",
        edition_title: "Edición crítica",
        historical_time: "siglo_xvi",
        historical_time_note: "Durante una guerra.",
        composition_date_from: 1605,
        composition_date_to: 1607,
        composition_date_note: "hacia 1606",
        edition_notes: ["Una nota sobre la edición.", "Otra nota,\nen dos líneas."],
        revisions: [
          %{
            date: "2021",
            people: "Muñoz Pons, Carlos; Tronch, Jesús",
            description: "Revisión en TEI-XML",
            note: "Con correcciones."
          },
          %{date: "2026-10-18", people: "Amelang, David", description: "Corrección"}
        ]
      })

    build_credits(play)
    build_witnesses(play)
    build_bibliography(play)
    build_places(play)
    build_paratexts(play)
    characters = build_cast(play)
    build_text(play, characters)

    PlayContent.refresh_derived(play.id)
    play
  end

  defp build_credits(play) do
    for {role, name, organization} <- [
          {"translator", "Sanderson, John D.", "Universidad de Málaga"},
          {"critical_editor", "Crítico, Carlos", "Universidad de Valencia"},
          {"digital_editor", "Amelang, David J.", nil},
          {"editor", "Editora, Elena", "Laboratorio"},
          {"reviewer", "Revisor, Raúl", nil},
          {"principal", "Oleza Simó, Joan", nil},
          {"researcher", "Investigadora, Inés", "Instituto"}
        ] do
      {:ok, _} =
        Catalogue.create_play_editor(%{
          play_id: play.id,
          role: role,
          person_name: name,
          organization: organization
        })
    end

    {:ok, _} =
      Catalogue.create_play_source(%{
        play_id: play.id,
        title: "La comedia <<completa>>",
        author: "Autora, Ana",
        editor: "Sanderson, John D.",
        editor_role: "traductor",
        note: "Notas de la fuente.",
        publisher: "Miguel Seguí",
        pub_place: "Barcelona",
        pub_date: "1908",
        language: "Español",
        distributor: "Canon 60"
      })
  end

  defp build_witnesses(play) do
    for {siglum, type} <- [{"A", "manuscript"}, {"B", "early_edition"}] do
      {:ok, _} =
        Playcode.Witnesses.create_witness(%{
          play_id: play.id,
          siglum: siglum,
          title: "Comedia completa,\nprimera parte (#{siglum})",
          normalized_title: "Comedia completa #{siglum}",
          attribution: "Autora, Ana",
          pub_place: "Madrid",
          publisher: "Juan de la Cuesta",
          date: "1605",
          format: "4º",
          witness_type: type,
          shelfmark: "BNE R/#{siglum}",
          note: "Testigo #{siglum}."
        })
    end
  end

  defp build_bibliography(play) do
    {:ok, _} =
      Bibliography.create_entry_for_play(
        play.id,
        %{
          kind: "modern_edition",
          pub_type: "scholarly_edition",
          language: "es",
          monogr_author: "Autora, Ana",
          monogr_title: "Teatro completo",
          monogr_editors: "Morris, Brian; Gill, Roma",
          monogr_translators: "Sanderson, John D.",
          edition: "2ª ed.",
          volume: "3",
          volumes_total: "5",
          pub_place: "Madrid",
          publisher: "Cátedra",
          year_text: "1999",
          series: "Letras Hispánicas",
          siglum: "M",
          public_note: "Edición de referencia.",
          note: "Nota privada de la entrada."
        },
        %{volume: "2", pages: "45-120", note: "Nota privada del vínculo."}
      )

    {:ok, _} =
      Bibliography.create_entry_for_play(play.id, %{
        kind: "criticism",
        pub_type: "article",
        language: "en",
        analytic_author: "Crítica, Clara",
        analytic_title: "On the complete comedy",
        analytic_editors: "Editor, Ed",
        analytic_translators: "Traductor, Tomás",
        original_title: "Sobre la comedia completa",
        monogr_title: "Bulletin of the Comedia",
        issue: "12",
        pages: "1-20",
        year_text: "2001",
        url: "https://example.org/article",
        url_accessed_on: "2026-10-18"
      })
  end

  defp build_places(play) do
    parent = place_fixture(%{"name" => "Italia", "type" => "country"})

    place =
      place_fixture(%{
        "names" => [
          %{"name" => "Venecia", "language" => "es", "is_preferred" => "true", "position" => 0},
          %{"name" => "Venetia", "language" => "la", "is_historical" => "true", "position" => 1}
        ],
        "type" => "city",
        "latitude" => 45.4375,
        "longitude" => 12.3358,
        "is_fictional" => "true",
        "authority" => "wikidata",
        "authority_id" => "Q641",
        "note" => "La ciudad de los canales.",
        "parent_place_id" => parent.id
      })

    {:ok, _} =
      Places.link_place(play.id, place.id, %{"role" => "mentioned", "note" => "Se nombra."})
  end

  defp build_paratexts(play) do
    for attrs <- [
          %{
            kind: "dedicatoria",
            heading: "DEDICATORIA",
            content: "Al <<lector>>,\ncon afecto.\n\nSegundo párrafo."
          },
          %{kind: "head_title", heading: "LA COMEDIA COMPLETA"},
          %{kind: "lugar_accion", heading: "ESCENA:", content: "Un bosque de Venecia."},
          %{kind: "epilogo", heading: "EPÍLOGO", content: "Fin de la obra.", back: true}
        ] do
      {:ok, _} = Catalogue.create_paratext(Map.put(attrs, :play_id, play.id))
    end
  end

  defp build_cast(play) do
    {:ok, _} =
      PlayContent.create_division(%{
        play_id: play.id,
        type: "elenco",
        title: "DRAMATIS PERSONAE",
        position: 0
      })

    for {attrs, position} <-
          Enum.with_index([
            %{xml_id: "ANA", name: "Ana", description: "dama <<joven>>"},
            %{xml_id: "BLAS", name: "Blas", actor: "Mr. Betterton"},
            %{xml_id: "CRIADO", name: "Criado", is_hidden: true}
          ]) do
      {:ok, character} =
        PlayContent.create_character(Map.merge(attrs, %{play_id: play.id, position: position}))

      character
    end
  end

  defp build_text(play, [ana, blas, _criado]) do
    {:ok, act} =
      PlayContent.create_division(%{
        play_id: play.id,
        type: "acto",
        number: 1,
        title: "ACTO PRIMERO",
        position: 1
      })

    note!(play, %{division_id: act.id, offset: 4, n: "1", type: "editor", body: "El acto."})

    {:ok, scene} =
      PlayContent.create_division(%{
        play_id: play.id,
        parent_id: act.id,
        type: "escena",
        number: 1,
        title: "ESCENA I",
        position: 0
      })

    in_scene = %{play_id: play.id, division_id: scene.id}

    stage =
      element!(in_scene, %{type: "stage_direction", stage_type: "entrance", content: "Salen."})

    note!(play, %{element_id: stage.id, offset: 5, n: "2", type: "autor", body: "Salen."})

    speech = element!(in_scene, %{type: "speech", speaker_label: "ANA Y BLAS"})
    PlayContent.set_element_characters(speech.id, [ana.id, blas.id])

    note!(play, %{
      element_id: speech.id,
      offset: 3,
      n: "3",
      type: "traductor",
      term: "y",
      body: "Hablan a la vez.\n\nSegundo párrafo."
    })

    in_speech = Map.put(in_scene, :parent_id, speech.id)
    group = element!(in_speech, %{type: "line_group", verse_type: "redondilla"})
    in_group = Map.put(in_scene, :parent_id, group.id)

    first =
      verse!(in_group, %{
        content: "Uno <<en cursiva>>",
        line_number: 1,
        line_id: "cc-0001",
        part: "I"
      })

    note!(play, %{
      element_id: first.id,
      offset: 3,
      n: "4",
      type: "variante",
      variant_type: "sustitucion",
      range_end: "#cc-0002",
      body: "Variante dudosa.",
      readings: [
        %{lemma: true, wit: "#A", text: "Uno"},
        %{wit: "#B", text: "Un", note: "Errata."}
      ]
    })

    verse!(in_group, %{content: "dos", line_number: 1, line_id: "cc-0002", part: "F"})

    verse!(in_group, %{
      content: "tres <stage type=\"business\">Llora.</stage> sigue",
      line_number: 2,
      line_id: "cc-0003",
      rend: "indent"
    })

    verse!(in_group, %{content: "cuatro todo aparte", line_number: 3, is_aside: true})

    verse!(in_group, %{content: "cinco <aside>a medias</aside> dicho", line_number: 4})

    noted =
      verse!(in_group, %{content: "seis <folio>del Folio</folio> fin", line_number: 5})

    note!(play, %{element_id: noted.id, offset: 4, n: "5", type: "editor", body: "Seis."})

    element!(in_speech, %{
      type: "prose",
      content: "Prosa en una línea,\nen otra <lb n=\"12\"/>y en la impresa."
    })

    element!(in_scene, %{type: "prose", content: "Una pantomima sin voz."})
    element!(%{play_id: play.id, division_id: act.id}, %{type: "trailer", content: "FIN"})
  end

  defp element!(within, attrs) do
    position = PlayContent.next_element_position(within.division_id, within[:parent_id])

    {:ok, element} =
      PlayContent.create_element(within |> Map.merge(attrs) |> Map.put(:position, position))

    element
  end

  defp verse!(within, attrs), do: element!(within, Map.put(attrs, :type, "verse_line"))

  defp note!(play, attrs) do
    {:ok, note} = PlayContent.create_note(Map.put(attrs, :play_id, play.id))
    note
  end

  # Where two snapshots differ, as {path, expected, actual}: the whole snapshot is too big
  # for a failure to show it.
  defp differences(expected, actual, path \\ [])
  defp differences(same, same, _path), do: []

  defp differences(%{} = expected, %{} = actual, path) do
    for key <- Enum.uniq(Map.keys(expected) ++ Map.keys(actual)),
        difference <- differences(expected[key], actual[key], path ++ [key]),
        do: difference
  end

  defp differences(expected, actual, path)
       when is_list(expected) and is_list(actual) and length(expected) == length(actual) do
    [expected, actual]
    |> Enum.zip()
    |> Enum.with_index()
    |> Enum.flat_map(fn {{e, a}, i} -> differences(e, a, path ++ [i]) end)
  end

  defp differences(expected, actual, path), do: [{path, expected, actual}]

  # --- The snapshot ---

  # The play as Playcode's public functions give it back, in their order.
  defp snapshot(play_id) do
    play = Catalogue.get_play_with_all!(play_id)
    gazetteer = Places.gazetteer()

    %{
      play: play |> fields() |> Map.put(:parent, play.parent_play && play.parent_play.code),
      editors: Enum.map(play.editors, &fields/1),
      sources: Enum.map(play.sources, &fields/1),
      witnesses: Enum.map(play.witnesses, &fields/1),
      paratexts: Enum.map(play.paratexts, &fields/1),
      characters: Enum.map(PlayContent.list_characters(play_id), &fields/1),
      bibliography:
        for {_kind, groups} <- Bibliography.list_for_play(play_id),
            {_language, links} <- groups,
            link <- links do
          link |> fields() |> Map.put(:entry, fields(link.entry))
        end,
      places:
        for link <- play.play_places do
          ancestors = Enum.map(Places.ancestors(link.place, gazetteer), &place/1)

          link
          |> fields()
          |> Map.put(:place, link.place |> place() |> Map.put(:ancestors, ancestors))
        end,
      divisions: Enum.map(PlayContent.load_play_content(play_id), &division/1)
    }
  end

  defp place(place), do: place |> fields() |> Map.put(:names, Enum.map(place.names, &fields/1))

  defp division(division) do
    division
    |> fields()
    |> Map.merge(%{
      notes: Enum.map(division.notes, &fields/1),
      elements: Enum.map(division.loaded_elements, &element/1),
      children: Enum.map(division.children, &division/1)
    })
  end

  defp element(element) do
    element
    |> fields()
    |> Map.merge(%{
      who: Enum.map(element.element_characters, & &1.character.xml_id),
      notes: Enum.map(element.notes, &fields/1),
      children: element.children |> loaded() |> Enum.map(&element/1)
    })
  end

  # load_play_content/1 loads three levels of elements: speech, line group, verse line.
  defp loaded(%Ecto.Association.NotLoaded{}), do: []
  defp loaded(children), do: children

  # Every stored column but the dropped ones, embedded rows (revisions, readings) alike.
  defp fields(%module{} = row) do
    for field <- module.__schema__(:fields) -- (@dropped ++ Map.get(@private, module, [])),
        into: %{} do
      {field, row |> Map.fetch!(field) |> plain()}
    end
  end

  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)

  defp plain(%module{} = struct) do
    if function_exported?(module, :__schema__, 1), do: fields(struct), else: struct
  end

  defp plain(value), do: value
end
