defmodule Playcode.AlignmentTest do
  # Proof of concept (problem 5, docs/superpowers/specs/2026-11-08-translation-alignment-design.md):
  # the aligner reads plain speech lists, so these tests build them by hand.
  use ExUnit.Case, async: true

  alias Playcode.Alignment

  # The spec's invented example: sp1–sp5 spoken by Philo, Cleopatra, Antony, Cleopatra, Antony.
  @original %{
    characters: [
      %{id: "philo", name: "Philo"},
      %{id: "cleo", name: "Cleopatra"},
      %{id: "antony", name: "Antony"}
    ],
    speeches: [
      %{id: "sp1", act: "act-0", scene: "scene-0", speakers: ["philo"], words: 40},
      %{id: "sp2", act: "act-0", scene: "scene-0", speakers: ["cleo"], words: 8},
      %{id: "sp3", act: "act-0", scene: "scene-0", speakers: ["antony"], words: 30},
      %{id: "sp4", act: "act-0", scene: "scene-0", speakers: ["cleo"], words: 12},
      %{id: "sp5", act: "act-0", scene: "scene-0", speakers: ["antony"], words: 20}
    ]
  }

  test "pairs characters across languages by name" do
    french = %{
      characters: [
        %{id: "f-antoine", name: "Antoine"},
        %{id: "f-cleo", name: "Cléopâtre"},
        %{id: "f-philon", name: "Philon"}
      ],
      speeches: []
    }

    assert Alignment.align(@original, french).characters == %{
             "f-antoine" => "antony",
             "f-cleo" => "cleo",
             "f-philon" => "philo"
           }
  end

  # Step 3: a researcher's corrections, by the original character's xml:id, come before
  # the rule; "no original" takes a character out; a pointer to no one counts as none.
  test "a correction wins over the rule, and one naming no one is no correction" do
    original = %{
      @original
      | characters: Enum.map(@original.characters, &Map.put(&1, :xml_id, String.upcase(&1.id)))
    }

    french = %{
      characters: [
        %{id: "f-antoine", name: "Antoine", original_xml_id: "CLEO"},
        %{id: "f-cleo", name: "Cléopâtre", no_original: true},
        %{id: "f-philon", name: "Philon", original_xml_id: "GONE"}
      ],
      speeches: []
    }

    assert Alignment.align(original, french).characters == %{
             "f-antoine" => "cleo",
             "f-philon" => "philo"
           }
  end

  # 0038/0084's last scene: neither name matches, both speak only there, so how much each
  # speaks is what tells them apart.
  test "two renamed roles in one scene pair by how much they speak" do
    scene = fn speakers, prefix ->
      for {who, i} <- Enum.with_index(speakers),
          do: %{id: "#{prefix}#{i}", act: "act-0", scene: nil, speakers: [who], words: 10}
    end

    # The two roles in the play's last twentieth, the Countryman with 8 speeches and the
    # Guardsman with 2, as in the files.
    lines = fn cleo, countryman, guard ->
      List.duplicate(cleo, 400) ++
        List.flatten(List.duplicate([countryman, cleo], 8) ++ List.duplicate([guard, cleo], 2))
    end

    original = %{
      characters: [
        %{id: "cleo", name: "CLEOPATRA"},
        %{id: "countryman", name: "A COUNTRYMAN"},
        %{id: "guard", name: "GUARDSMAN"}
      ],
      speeches: scene.(lines.("cleo", "countryman", "guard"), "o")
    }

    french = %{
      characters: [
        %{id: "f-cleo", name: "CLÉOPATRE"},
        %{id: "f-paysan", name: "UN PAYSAN"},
        %{id: "f-garde", name: "UN GARDE"}
      ],
      speeches: scene.(lines.("f-cleo", "f-paysan", "f-garde"), "f")
    }

    assert %{"f-paysan" => "countryman", "f-garde" => "guard"} =
             Alignment.align(original, french).characters
  end

  test "a speaker repeated after a stage direction points at the one original speech" do
    french = %{
      characters: [
        %{id: "f-philon", name: "Philon"},
        %{id: "f-cleo", name: "Cléopâtre"},
        %{id: "f-antoine", name: "Antoine"}
      ],
      speeches: [
        %{id: "f1", act: "act-0", scene: "scene-0", speakers: ["f-philon"], words: 42},
        %{id: "f2", act: "act-0", scene: "scene-0", speakers: ["f-cleo"], words: 9},
        %{id: "f3", act: "act-0", scene: "scene-0", speakers: ["f-antoine"], words: 14},
        %{id: "f4", act: "act-0", scene: "scene-0", speakers: ["f-antoine"], words: 15},
        %{id: "f5", act: "act-0", scene: "scene-0", speakers: ["f-cleo"], words: 13},
        %{id: "f6", act: "act-0", scene: "scene-0", speakers: ["f-antoine"], words: 22}
      ]
    }

    alignment = Alignment.align(@original, french)

    assert Enum.find(alignment.speeches, &(&1.id == "f4")).kind == :split

    assert pairs(alignment) == [
             {"f1", "sp1"},
             {"f2", "sp2"},
             {"f3", "sp3"},
             {"f4", "sp3"},
             {"f5", "sp4"},
             {"f6", "sp5"}
           ]
  end

  test "a cut speech is paired with nothing, and the speeches after it stay in place" do
    spanish = %{
      characters: [
        %{id: "s-filon", name: "Filón"},
        %{id: "s-cleo", name: "Cleopatra"},
        %{id: "s-antonio", name: "Antonio"}
      ],
      speeches: [
        %{id: "s1", act: "act-0", scene: "scene-0", speakers: ["s-filon"], words: 38},
        %{id: "s2", act: "act-0", scene: "scene-0", speakers: ["s-cleo"], words: 7},
        %{id: "s3", act: "act-0", scene: "scene-0", speakers: ["s-antonio"], words: 31},
        %{id: "s5", act: "act-0", scene: "scene-0", speakers: ["s-antonio"], words: 19}
      ]
    }

    alignment = Alignment.align(@original, spanish)

    assert pairs(alignment) == [{"s1", "sp1"}, {"s2", "sp2"}, {"s3", "sp3"}, {"s5", "sp5"}]
    assert alignment.unpaired == ["sp4"]
  end

  defp pairs(%{speeches: speeches}), do: Enum.map(speeches, &{&1.id, &1.original})
end
