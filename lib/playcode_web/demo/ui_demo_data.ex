defmodule PlaycodeWeb.Demo.UIDemoData do
  @moduledoc false

  alias Playcode.Catalogue.Play

  def play() do
    %Play{
      id: "00000000-0000-0000-0000-000000000001",
      title: "La Dama Boba",
      code: "DAMA01",
      author_name: "Lope de Vega",
      language: "es",
      verse_count: 3021,
      is_verse: true,
      publication_date: "1613",
      pub_place: "Madrid",
      author_attribution: "atrib.",
      editors: [
        %{person_name: "Jane Editor", role: "editor", organization: "EMOTHE"},
        %{person_name: "John Principal", role: "principal", organization: nil}
      ],
      sources: [
        %{note: "Edición digital preparada a partir de la tradición impresa."}
      ],
      paratexts: [
        %{heading: "Nota editorial", content: "Texto de muestra para la vista previa del diseño."}
      ]
    }
  end

  def plays_list() do
    [
      play(),
      %Play{
        id: "00000000-0000-0000-0000-000000000002",
        title: "El Perro del Hortelano",
        code: "PERRO01",
        author_name: "Lope de Vega",
        language: "es",
        verse_count: 3250,
        is_verse: true
      },
      %Play{
        id: "00000000-0000-0000-0000-000000000003",
        title: "La Vida es Sueño",
        code: "VIDA01",
        author_name: "Calderón de la Barca",
        language: "es",
        verse_count: 0,
        is_verse: false
      }
    ]
  end

  def characters() do
    [
      %{name: "Finea", description: "dama", is_hidden: false},
      %{name: "Nise", description: "dama", is_hidden: false},
      %{name: "Liseo", description: "caballero", is_hidden: false},
      %{name: "Criado", description: nil, is_hidden: true}
    ]
  end

  def statistic() do
    %{
      computed_at: ~U[2026-02-19 12:00:00Z],
      data: %{
        "num_acts" => 3,
        "scenes" => %{
          "total" => 9,
          "per_act" => [
            %{"act" => 1, "count" => 3},
            %{"act" => 2, "count" => 3},
            %{"act" => 3, "count" => 3}
          ]
        },
        "total_verses" => 3021,
        "total_stage_directions" => 120,
        "split_verses" => 42,
        "total_asides" => 7,
        "aside_verses" => 15,
        "verse_distribution" => [
          %{"act" => 1, "count" => 980},
          %{"act" => 2, "count" => 1011},
          %{"act" => 3, "count" => 1030}
        ],
        "total_prose_fragments" => 2,
        "prose_fragments" => [%{"act" => 1, "count" => 1}, %{"act" => 3, "count" => 1}],
        "character_appearances" => [
          %{"name" => "Finea", "speeches" => 120},
          %{"name" => "Nise", "speeches" => 95},
          %{"name" => "Liseo", "speeches" => 70}
        ]
      }
    }
  end
end
