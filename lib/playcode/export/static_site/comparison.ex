defmodule Playcode.Export.StaticSite.Comparison do
  @moduledoc """
  The site's comparison page (`plays/<CODE>/compare.html`): a play beside its original,
  scrolling together through `assets/js/sync_scroll.mjs`, inlined here, so the page needs
  no other file and a change to the script moves the site's fingerprint. Speeches carry
  their act's key (`data-sync-act`) and, from `Playcode.Alignment`, the place of the
  original speech they go with (`data-pair`); headings their own key (`data-sync-div`),
  as on Playcode's comparison.
  """

  use Phoenix.Component

  import Playcode.Export.StaticSite.Bilingual

  alias Playcode.Alignment
  alias Playcode.Export.StaticSite.Components
  alias Playcode.Export.StaticSite.Edition
  alias Playcode.PlayContent.{Division, Element, InlineMarkup}

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

  @doc """
  A panel's name, its part before its title (`Original: …`, `Version: …`): a version often
  keeps its original's title.
  """
  def panel_name(play, 0), do: join([tp("Original"), title(play)], ": ")

  def panel_name(play, _) do
    {es, en} = Components.kind_word(play)
    join([{String.capitalize(es), String.capitalize(en)}, title(play)], ": ")
  end

  defp title(play), do: {InlineMarkup.plain(play.title), InlineMarkup.plain(play.title)}

  @doc """
  The translation menu's entries, `{play, label}`, each label `{spanish, english}`: each
  by its title and language, and by its code too where two would read alike.
  """
  def menu(plays) do
    labelled = Enum.map(plays, &{&1, menu_label(&1)})
    counts = Enum.frequencies_by(labelled, &elem(&1, 1))

    for {play, label} <- labelled,
        do:
          {play,
           if(counts[label] > 1, do: join([label, {play.code, play.code}], " — "), else: label)}
  end

  defp menu_label(%{language: language} = play) when language in [nil, ""], do: title(play)

  defp menu_label(play) do
    {es, en} = Components.language(play.language)
    join([title(play), {"(#{es})", "(#{en})"}], " ")
  end

  attr :edition, :map, required: true
  attr :name, :any, required: true, doc: "the panel's name (`panel_name/2`)"
  attr :prefix, :string, default: nil

  @doc """
  A panel's text. Both plays number their ids alike (`act-1`, `l1`, `note-1`), so the
  translation's carry a `prefix`: its note buttons open its own notes, its line links
  scroll its own panel. Text is escaped, so ` id="` is only ever markup.
  """
  def text(assigns) do
    assigns =
      assign(assigns, :label, attrs(join([tp("Notes"), assigns.name], " — "), "aria-label"))

    html =
      ~H"""
      <Components.full_text edition={@edition} notes_label={@label} />
      """
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assigns = assign(assigns, :html, Phoenix.HTML.raw(own_ids(html, assigns.prefix)))
    ~H"{@html}"
  end

  defp own_ids(html, nil), do: html

  defp own_ids(html, prefix) do
    String.replace(html, ~r/ (id|popovertarget)="|href="#/, fn
      ~s(href="#) -> ~s(href="#) <> prefix
      attribute -> attribute <> prefix
    end)
  end

  # Starts the sync. A fragment `#s<n>` opens the original's panel at its speech `n`, the
  # other following; the translation menu opens the page it names at the original's
  # speech now at the top, so switching translation keeps the place.
  @start ~S"""
  document.addEventListener("DOMContentLoaded", () => {
    const original = document.querySelector('[data-panel="panel-0"]')
    const place = location.hash.match(/^#s(\d+)$/)
    const speech = place && original.querySelector(`[data-pair="${place[1]}"]`)
    if (speech) original.scrollTop += speech.getBoundingClientRect().top - original.getBoundingClientRect().top
    syncPanels(document.getElementById("sync-scroll"))

    const menu = document.querySelector("[data-compare-menu]")
    if (menu) menu.addEventListener("change", () => {
      const top = topAnchor(original, "[data-pair]")
      location.href = menu.value + (top ? "#s" + top.dataset.pair : "")
    })
  })
  """

  @doc "The page's script: the scroll sync and the translation menu."
  def script, do: @sync_scroll <> "\n" <> @start
end
