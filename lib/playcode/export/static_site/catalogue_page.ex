defmodule Playcode.Export.StaticSite.CataloguePage do
  @moduledoc """
  The catalogue, `index.html`, and its record index (`Records`), written whole on every
  Generate from the published plays' rows. `Fingerprint` leaves this module out, so a
  change to the catalogue rebuilds no play: no play page may call it.
  """
  use Phoenix.Component

  import Playcode.Export.StaticSite.Bilingual

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.{Components, Pages, Records, Search}
  alias Playcode.Performances.Performance
  alias PlaycodeWeb.PlayLabels

  embed_templates "catalogue_page/*"

  @doc "Writes `index.html` and the record index into `dir`; returns the record index's size."
  def write(plays, dir, site) do
    by_id = Map.new(plays, &{&1.id, &1})
    entries = Records.entries(plays, Map.new(plays, &{&1.id, by_id[root_id(&1, by_id)]}))

    html =
      %{
        site: site,
        works: works(plays),
        lists: lists(entries),
        count: length(plays),
        authors:
          plays |> Enum.map(& &1.author_name) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length(),
        __changed__: nil
      }
      |> catalogue()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> Pages.strip_annotations()

    File.write!(Path.join(dir, "index.html"), html)
    Records.write(dir, entries)
  end

  # What catalogue.js says, `{spanish, english}` as JSON pairs: its count and a row's
  # passages. `more` keeps its `%{count}` for the script to fill.
  defp catalogue_words do
    words = %{
      of: tp("of"),
      play: tp("play"),
      plays: tp("plays"),
      passage: tp("passage"),
      passages: tp("passages"),
      searching: tp("Searching…"),
      open: tp("Show the passages"),
      more: tp("Show the other %{count}", count: "%{count}"),
      unavailable: tp("Text search is unavailable."),
      note: tp("note"),
      works: tp("Plays"),
      texts: tp("In the texts"),
      character: tp("Character"),
      place: tp("Place of action"),
      remove: tp("Remove")
    }

    Jason.encode!(pairs(words))
  end

  # The catalogue form's three kinds of control. Each is named by its label; a range's two
  # boxes by their aria-labels, its label pointing at the first.
  attr :name, :string, required: true
  attr :label, :any, required: true
  attr :hint, :any, default: nil
  attr :suggest, :boolean, default: false, doc: "a datalist, which catalogue.js fills"

  defp search_text(assigns) do
    ~H"""
    <label for={"c-" <> @name}>{@label} <small :if={@hint}>{@hint}</small></label>
    <input
      type="text"
      id={"c-" <> @name}
      name={@name}
      list={@suggest && "dl-" <> @name}
      autocomplete="off"
    />
    <datalist :if={@suggest} id={"dl-" <> @name}></datalist>
    """
  end

  attr :name, :string, required: true
  attr :label, :any, required: true
  attr :options, :list, required: true, doc: "`{value, {spanish, english}}`, the first \"All\""

  defp search_list(assigns) do
    ~H"""
    <label for={"c-" <> @name}>{@label}</label>
    <select id={"c-" <> @name} name={@name}>
      <option :for={{value, label} <- @options} value={value} {attrs(label, "label")}></option>
    </select>
    """
  end

  attr :name, :string, required: true
  attr :label, :any, required: true
  attr :from, :any, required: true, doc: "the first box's aria-label, `{spanish, english}`"
  attr :to, :any, required: true

  defp search_range(assigns) do
    ~H"""
    <label for={"c-" <> @name <> "-from"}>{@label}</label>
    <div class="range">
      <input
        type="number"
        id={"c-" <> @name <> "-from"}
        name={@name <> "-from"}
        {Enum.uniq(ta("placeholder", "from") ++ attrs(@from, "aria-label"))}
      />
      <span aria-hidden="true">–</span>
      <input
        type="number"
        name={@name <> "-to"}
        {Enum.uniq(ta("placeholder", "to") ++ attrs(@to, "aria-label"))}
      />
    </div>
    """
  end

  defp pairs(%{} = map), do: Map.new(map, fn {key, value} -> {key, pairs(value)} end)
  defp pairs({es, en}), do: [es, en]

  attr :play, :map, required: true
  attr :lead, :boolean, default: false
  attr :compare, :string, default: nil, doc: "the code of the play the Compare link opens"

  def catalogue_entry(assigns) do
    ~H"""
    <div
      class="entry"
      data-play
      data-code={@play.code}
    >
      <span class="tag">{@play.language}</span>
      <a class={["entry-title", @lead && "lead"]} href={"plays/#{@play.code}/index.html"}>
        {@play.title}
      </a>
      <span class="code">{@play.code}</span>
      <a
        :if={@compare}
        class="compare"
        href={"plays/#{@compare}/compare.html"}
        {ta(["aria-label", "title"], "Compare")}
      >
        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path
            fill-rule="evenodd"
            d="M13.2 2.24a.75.75 0 0 0 .04 1.06l2.1 1.95H6.75a.75.75 0 0 0 0 1.5h8.59l-2.1 1.95a.75.75 0 1 0 1.02 1.1l3.5-3.25a.75.75 0 0 0 0-1.1l-3.5-3.25a.75.75 0 0 0-1.06.04Zm-6.4 8a.75.75 0 0 0-1.06-.04l-3.5 3.25a.75.75 0 0 0 0 1.1l3.5 3.25a.75.75 0 1 0 1.02-1.1l-2.1-1.95h8.59a.75.75 0 0 0 0-1.5H4.66l2.1-1.95a.75.75 0 0 0 .04-1.06Z"
            clip-rule="evenodd"
          />
        </svg>
      </a>
      <span :if={Components.kind(@play) != "original"} class="tag">
        {html(Components.kind_word(@play))}
      </span>
      <span :if={!Play.has_text?(@play)} class="tag">{html(tp("no text"))}</span>
      <span class="meta">{entry_meta(@play)}</span>
      <span :if={@lead} class="author">{@play.author_name}</span>
    </div>
    """
  end

  defp entry_meta(play) do
    form =
      case Play.form(play) do
        nil ->
          nil

        "verse" when is_integer(play.verse_count) and play.verse_count > 0 ->
          same("#{Components.number(play.verse_count)} vv.")

        form ->
          pair(fn -> PlayLabels.form_label(form) end)
      end

    years = if years = Play.composition_years(play), do: same(years)

    case Enum.reject([years, form], &is_nil/1) do
      [] -> nil
      parts -> parts |> join(" · ") |> html()
    end
  end

  # One entry per work: each published play under the published play at the root of
  # its translation chain.
  defp works(plays) do
    by_id = Map.new(plays, &{&1.id, &1})

    plays
    |> Enum.group_by(&root_id(&1, by_id))
    |> Enum.map(fn {root, members} ->
      lead = by_id[root]

      translations = members |> Enum.reject(&(&1.id == root)) |> StaticSite.translation_order()

      %{
        play: lead,
        translations: translations,
        # The comparison the lead's Compare link opens: its first own derived play's with a
        # text, when the lead has one.
        compare:
          Play.has_text?(lead) &&
            Enum.find_value(
              translations,
              &(&1.parent_play_id == root && Play.has_text?(&1) && &1.code)
            ),
        sort_author: Search.normalise(lead.author_sort || lead.author_name),
        sort_title: Search.normalise(lead.title_sort || lead.title),
        date: lead.composition_date_from
      }
    end)
    |> Enum.sort_by(&{&1.sort_author, &1.sort_title})
  end

  # Follows parent_play_id to the root; on a cycle (hand-edited data) the play stands
  # alone as its own root.
  defp root_id(play, by_id), do: root_id(play, by_id, MapSet.new([play.id]), play.id)

  defp root_id(play, by_id, seen, start) do
    case by_id[play.parent_play_id] do
      nil ->
        play.id

      parent ->
        if parent.id in seen,
          do: start,
          else: root_id(parent, by_id, MapSet.put(seen, parent.id), start)
    end
  end

  # The options of the catalogue form's lists, by control name, from the record entries:
  # "All" first, then the values the published plays hold, each `{value, {spanish, english}}`.
  # The first four with their counts, most frequent first; the vocabularies in their own order.
  defp lists(entries) do
    witnesses = Enum.flat_map(entries, &Map.get(&1, :w, []))
    performances = Enum.flat_map(entries, &Map.get(&1, :r, []))
    all = tp("All")
    all_f = tpc("feminine", "All")

    %{
      "l" => [{"", all} | by_count(entries, :l, &Components.language/1, true)],
      "o" => [{"", all} | by_count(entries, :o, &Components.language/1, false)],
      "k" => [{"", all} | by_count(entries, :k, &Components.kind_label/1, true)],
      "s" => [{"", all_f} | by_count(entries, :s, &same/1, true)],
      "f" => [{"", all_f} | by_count(entries, :f, in_both(&PlayLabels.form_label/1), true)],
      "x" => [{"", all_f}, {"1", tp("With a text")}, {"0", tp("No text")}],
      "wt" => [
        {"", all}
        | in_order(
            witnesses,
            0,
            approved(witness_types()),
            in_both(&PlayLabels.witness_type_label/1)
          )
      ],
      "wf" => [{"", all} | in_order(witnesses, 4, formats(witnesses), &same/1)],
      "rc" => [
        {"", all_f}
        | in_order(performances, 2, approved(Performance.venue_types()), &venue_type_label/1)
      ],
      "h" => [
        {"", all}
        | in_order(
            entries,
            :h,
            approved(Play.historical_times()),
            in_both(&PlayLabels.historical_time_label/1)
          )
      ]
    }
  end

  defp by_count(entries, key, label, counted?) do
    entries
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.map(fn {value, n} ->
      {es, en} = label.(value)
      {value, if(counted?, do: {"#{es} (#{n})", "#{en} (#{n})"}, else: {es, en})}
    end)
  end

  # The vocabulary's values some row holds at `at`, a tuple's index or an entry's key.
  defp in_order(rows, at, vocabulary, label) do
    present = MapSet.new(rows, &if(is_atom(at), do: Map.get(&1, at), else: Enum.at(&1, at)))
    for value <- vocabulary, value in present, do: {value, label.(value)}
  end

  # The lists' order in the mock the researcher approved (2026-11-17); the admin's forms keep
  # each vocabulary's own. A value the mock does not name goes last.
  @approved ~w(loose early_edition collection_single_author collection_several_authors collection
               manuscript autograph copy
               commercial_theatre palace private_theatre street other unknown
               antiguedad_clasica antiguo_testamento edad_media siglo_xv siglo_xvi siglo_xvii
               tiempo_indeterminado tiempo_maravilloso tiempo_alegorico)

  defp approved(vocabulary),
    do:
      Enum.sort_by(vocabulary, fn value -> Enum.find_index(@approved, &(&1 == value)) || 999 end)

  defp witness_types,
    do:
      for(
        {_group, options} <- PlayLabels.witness_type_options(),
        {_, value} <- options,
        do: value
      )

  # Formats as written, by their number: 2º, 4º, 8º, 12º.
  defp formats(witnesses) do
    witnesses
    |> Enum.map(&Enum.at(&1, 4))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort_by(fn format ->
      case Integer.parse(format) do
        {n, _} -> {0, n, format}
        :error -> {1, 0, format}
      end
    end)
  end

  # A label function of the app's, said in both languages.
  defp in_both(label), do: fn value -> pair(fn -> label.(value) end) end

  # The mock's words: capitalised, and agreeing with «Todas» (la circunstancia escénica),
  # where the play pages' inline labels are lower case.
  defp venue_type_label("commercial_theatre"), do: tpc("venue type", "Commercial theatre")
  defp venue_type_label("public_theatre"), do: tpc("venue type", "Public theatre")
  defp venue_type_label("private_theatre"), do: tpc("venue type", "Private theatre")
  defp venue_type_label("palace"), do: tpc("venue type", "Palace")
  defp venue_type_label("university"), do: tpc("venue type", "University, inns of court")
  defp venue_type_label("street"), do: tpc("venue type", "Street, square")
  defp venue_type_label("other"), do: tpc("venue type", "Other")
  defp venue_type_label("unknown"), do: tpc("venue type", "Unknown")
end
