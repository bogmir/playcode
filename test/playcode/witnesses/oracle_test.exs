defmodule Playcode.Witnesses.OracleTest do
  @moduledoc """
  Every word FileMaker printed for a witness (`w3_ObrTes_Composicion`, emothe.uv.es's
  line) is in ours. Neither order nor punctuation is compared: test/playcode/witnesses_test.exs
  pins those. The sample is committed; the whole dump is git-ignored, so its sweep runs
  only where it is present. The import drops Jodelle's name on some plays; the oracle
  renders every record as FileMaker holds it, so it sees no such drop.
  """
  use ExUnit.Case, async: true

  alias Playcode.Import.Witnesses, as: Import
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness

  # `%{ref => [word]}` for every witness whose printed line lacks a word FileMaker printed.
  defp misses(dir) do
    {:ok, data} = Import.load(dir)
    attributions = Import.attributions(data)

    data.witnesses
    |> Enum.filter(&is_nil(Import.skip_reason(&1)))
    |> Map.new(fn row ->
      ours = Witnesses.plain(struct(Witness, Import.witness_attrs(row, attributions)))
      missing = MapSet.difference(words(row["w3_ObrTes_Composicion"]), words(ours))
      {"T03:" <> row["_kp_IdObraTestimonio"], Enum.sort(missing)}
    end)
    |> Map.reject(fn {_ref, missing} -> missing == [] end)
  end

  defp words(text) do
    ~r/[\p{L}\p{N}]+/u
    |> Regex.scan(text |> String.replace(~r/<[^>]*>/, " ") |> String.downcase())
    |> List.flatten()
    |> MapSet.new()
  end

  test "the committed sample" do
    assert misses("test/fixtures/filemaker/witnesses") == %{}
  end

  @tag :slow
  test "the whole FileMaker dump, where present" do
    if File.dir?("doc/ctce_dades"), do: assert(misses("doc/ctce_dades") == %{})
  end
end
