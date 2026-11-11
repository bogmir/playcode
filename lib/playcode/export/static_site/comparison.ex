defmodule Playcode.Export.StaticSite.Comparison do
  @moduledoc """
  The site's comparison page (`plays/<CODE>/compare.html`): a play beside its original,
  scrolling together through `assets/js/sync_scroll.mjs`, inlined here as
  `Export.CompareHtml` inlines it, so the page needs no other file and a change to the
  script moves the site's fingerprint. Speeches carry their act's key (`data-sync-act`)
  and, from `Playcode.Alignment`, the place of the original speech they go with
  (`data-pair`); headings their own key (`data-sync-div`), as on Playcode's comparison.
  """

  alias Playcode.Alignment
  alias Playcode.Export.StaticSite.Edition
  alias Playcode.PlayContent.{Division, Element}

  @sync_scroll_path Path.expand("../../../../assets/js/sync_scroll.mjs", __DIR__)
  @external_resource @sync_scroll_path
  @sync_scroll @sync_scroll_path |> File.read!() |> String.replace(~r/^export /m, "")

  @doc """
  Gives both editions their `sync`: the original's speeches their own places, the
  translation's the places of their originals when it is paired by speaker
  (`Alignment.paired?/1`), else none, so it scrolls by proportion.
  """
  def prepare(%Edition{} = original, %Edition{} = translation) do
    pairs =
      if Alignment.paired?(translation.play),
        do: Alignment.pair_places(original.divisions, translation.divisions),
        else: %{}

    {%{original | sync: sync(original.divisions, Alignment.own_places(original.divisions))},
     %{translation | sync: sync(translation.divisions, pairs)}}
  end

  # Each speech's act key and pair, each heading's key. A Folio-only speech is hidden
  # (the site's Folio switch starts off), so it gets neither: no box to scroll to.
  defp sync(divisions, pairs) do
    keyed =
      for {top, key} <- keyed(divisions),
          {division, div_key} <- [
            {top, key} | for({c, k} <- keyed(top.children), do: {c, "#{key}/#{k}"})
          ],
          do: {division, key, div_key}

    speeches =
      for {division, act, _} <- keyed,
          %{type: "speech"} = el <- Map.get(division, :loaded_elements, []),
          not Element.folio_only?(el),
          do: {el.id, act}

    %{
      act: Map.new(speeches),
      div: Map.new(keyed, fn {division, _, div_key} -> {division.id, div_key} end),
      pair: Map.take(pairs, Enum.map(speeches, &elem(&1, 0)))
    }
  end

  defp keyed(divisions), do: Enum.zip(divisions, Division.sync_keys(divisions))

  @doc "The page's script: the scroll sync, started on the panels once the page is read."
  def script do
    @sync_scroll <>
      ~s|\ndocument.addEventListener("DOMContentLoaded", () => syncPanels(document.getElementById("sync-scroll")))\n|
  end
end
