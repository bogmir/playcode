defmodule PlaycodeWeb.Components.StatisticsPanel do
  @moduledoc """
  A play's statistics as the static site draws them (`StaticSite.Components`): the figures
  in a row, the metrical synopsis, the characters and who shares the stage. Ported rather
  than reused, since the site prints both languages at once; the msgids are the site's.
  """
  use Phoenix.Component
  use Gettext, backend: PlaycodeWeb.Gettext

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.{Components, Edition}
  alias Playcode.PlayContent.InlineMarkup
  alias PlaycodeWeb.Components.PlayText
  alias PlaycodeWeb.PlayLabels

  attr :statistic, :map, required: true
  attr :play, :map, required: true

  def stats_panel(assigns) do
    data = if assigns.statistic, do: assigns.statistic.data, else: %{}
    words? = Play.form(assigns.play) != "verse" or (data["verses"] || 0) == 0
    range = Play.number_label(assigns.play, :range)

    assigns =
      assign(assigns,
        data: data,
        range: range,
        unit: if(words?, do: "words", else: "lines"),
        total: if(words?, do: data["words"] || 0, else: data["verses"])
      )

    ~H"""
    <div :if={@data != %{}} class="space-y-5">
      <.tiles data={@data} />
      <.synopsis
        :if={(@data["metrical_passages"] || []) != []}
        passages={@data["metrical_passages"]}
        range={@range}
      />
      <.characters characters={@data["characters"] || []} unit={@unit} total={@total} />
      <.presence data={@data} range={@range} />
    </div>
    """
  end

  defp panel(assigns) do
    ~H"""
    <section id={@id} class="rounded-box border border-base-300 bg-base-100 px-4 py-4">
      <h2 class="text-base font-semibold text-base-content">{@title}</h2>
      <p :if={assigns[:lede]} class="mb-3 mt-1 text-sm text-base-content/70">{@lede}</p>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp tiles(assigns) do
    s = assigns.data

    tiles =
      Enum.reject(
        [
          {s["num_acts"], gettext("acts")},
          {s["verses"], gettext("verses")},
          {length(s["metrical_passages"] || []), gettext("metrical passages")},
          {s["speeches"], gettext("speeches")},
          {length(s["characters"] || []), gettext("speaking characters")},
          {s["total_stage_directions"], gettext("stage directions")},
          {s["aside_verses"], gettext("verses in asides")}
        ],
        fn {value, _label} -> value in [nil, 0] end
      )

    assigns = assign(assigns, :tiles, tiles)

    ~H"""
    <dl id="tiles" class="flex flex-wrap border-y border-base-300 py-1">
      <div :for={{value, label} <- @tiles} class="flex flex-col-reverse py-2 pr-8">
        <dt class="text-xs text-base-content/70">{label}</dt>
        <dd class="font-serif text-2xl font-semibold tabular-nums">{Components.number(value)}</dd>
      </div>
    </dl>
    """
  end

  # The corpus's three commonest forms keep a colour each, every other form is grey.
  @coloured_forms %{
    "redondilla" => "f-redondilla",
    "romance" => "f-romance",
    "romance_tirada" => "f-romance",
    "quintilla" => "f-quintilla"
  }

  defp form_colour(form), do: Map.get(@coloured_forms, form, "f-other")

  defp synopsis(assigns) do
    passages = assigns.passages
    total = passages |> Enum.map(& &1["verses"]) |> Enum.sum() |> max(1)

    # By label, so romance and romance_tirada, both "Romance", are one form.
    forms =
      passages
      |> Enum.group_by(&PlayLabels.verse_form_label(&1["form"]))
      |> Enum.map(fn {label, [first | _] = group} ->
        {label, form_colour(first["form"]), group |> Enum.map(& &1["verses"]) |> Enum.sum()}
      end)
      |> Enum.sort_by(&(-elem(&1, 2)))

    segments =
      passages
      |> Enum.with_index()
      |> Enum.map(fn {passage, i} ->
        %{
          sep: i > 0 and Enum.at(passages, i - 1)["act"] != passage["act"],
          colour: form_colour(passage["form"]),
          verses: passage["verses"],
          title:
            "#{PlayLabels.verse_form_label(passage["form"])}#{verses_range(passage, assigns.range)} · " <>
              ngettext("%{count} verse", "%{count} verses", passage["verses"]),
          label:
            if(passage["verses"] / total > 0.06, do: PlayLabels.verse_form_label(passage["form"]))
        }
      end)

    assigns = assign(assigns, segments: segments, forms: forms, total: total)

    ~H"""
    <.panel
      id="synopsis"
      title={gettext("Metrical synopsis")}
      lede={
        gettext("The verse forms in order, each passage drawn to scale. Dashed lines mark the acts.")
      }
    >
      <div
        class="stat-band"
        role="img"
        aria-label={gettext("Metrical synopsis drawn to scale; the table below lists every passage.")}
      >
        <%= for segment <- @segments do %>
          <span :if={segment.sep} class="sep"></span>
          <span
            class={["pass", segment.colour]}
            style={"flex-grow: #{segment.verses}"}
            title={segment.title}
          >
            <span :if={segment.label}>{segment.label}</span>
          </span>
        <% end %>
      </div>
      <ul class="my-3 flex flex-wrap gap-x-5 gap-y-1 text-sm text-base-content/80">
        <li :for={{label, colour, verses} <- @forms}>
          <i class={["mr-1.5 inline-block size-2.5 rounded-sm align-baseline", colour]}></i>
          <b class="font-semibold text-base-content">{label}</b>
          {Components.number(verses)} vv. · {percent(verses, @total)}
        </li>
      </ul>
      <details class="border-t border-base-300 pt-2">
        <summary class="cursor-pointer text-sm font-semibold text-primary">
          {gettext("The %{count} passages, one by one", count: length(@passages))}
        </summary>
        <table class="table table-sm mt-2">
          <thead>
            <tr>
              <th>{gettext("Act")}</th>
              <th>{gettext("Form")}</th>
              <th>vv.</th>
              <th class="text-right">{gettext("Verses")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={passage <- @passages}>
              <td>{passage["act"] && Edition.roman(passage["act"])}</td>
              <td>
                <i class={["mr-1.5 inline-block size-2.5 rounded-sm", form_colour(passage["form"])]}></i>{PlayLabels.verse_form_label(
                  passage["form"]
                )}
              </td>
              <td>{range(passage)}</td>
              <td class="text-right tabular-nums">{Components.number(passage["verses"])}</td>
            </tr>
          </tbody>
        </table>
      </details>
      <p class="mt-3 text-sm text-base-content/70">
        {gettext(
          "Rhyme is not encoded, so two consecutive romances with different assonance show as one passage."
        )}
      </p>
    </.panel>
    """
  end

  defp characters(assigns) do
    characters =
      assigns.characters
      |> Enum.sort_by(&(-&1[assigns.unit]))
      |> Enum.map(&Map.put(&1, "main_forms", main_forms(&1["forms"])))

    max = characters |> Enum.map(& &1[assigns.unit]) |> Enum.max(fn -> 1 end) |> max(1)
    forms? = Enum.any?(characters, &(&1["main_forms"] != ""))
    assigns = assign(assigns, characters: characters, max: max, forms?: forms?)

    ~H"""
    <.panel
      :if={@characters != []}
      id="characters"
      title={gettext("Characters")}
      lede={characters_lede(@unit, length(@characters))}
    >
      <div class="overflow-x-auto" tabindex="0" role="region" aria-label={gettext("Characters")}>
        <table class="table table-sm">
          <thead>
            <tr>
              <th>{gettext("Character")}</th>
              <th class="text-right">{gettext("Speeches")}</th>
              <th class="text-right">{gettext("Lines")}</th>
              <th class="text-right">{gettext("Words")}</th>
              <th>{gettext("Share of the play")}</th>
              <th>{gettext("First speaks")}</th>
              <th :if={@forms?}>{gettext("Main forms")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={character <- @characters}>
              <th scope="row" class="font-serif text-left font-semibold">
                <PlayText.inline_content text={character["name"]} />
              </th>
              <td class="text-right tabular-nums">{Components.number(character["speeches"])}</td>
              <td class="text-right tabular-nums">{Components.number(character["lines"])}</td>
              <td class="text-right tabular-nums">{Components.number(character["words"])}</td>
              <td
                class="min-w-36 whitespace-nowrap"
                title={share_title(character[@unit], @total, @unit)}
              >
                <span class="mr-1.5 inline-block h-2 w-[calc(100%-3rem)] rounded-sm bg-base-300 align-middle">
                  <span
                    class="block h-full rounded-sm bg-primary"
                    style={"width: #{round(character[@unit] / @max * 100)}%"}
                  ></span>
                </span>{percent(character[@unit], @total)}
              </td>
              <td>{first_speaks(character["first"])}</td>
              <td :if={@forms?}>{character["main_forms"]}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </.panel>
    """
  end

  defp characters_lede("lines", n),
    do:
      gettext(
        "The %{n} speaking characters, those with the most lines first. A shared verse counts for each speaker.",
        n: n
      )

  defp characters_lede("words", n),
    do:
      gettext(
        "The %{n} speaking characters, those with the most words first. A shared verse counts for each speaker.",
        n: n
      )

  defp share_title(n, total, "lines"), do: gettext("%{n} of %{total} lines", n: n, total: total)
  defp share_title(n, total, "words"), do: gettext("%{n} of %{total} words", n: n, total: total)

  # "I.2, 144": the act, its scene when it has scenes, and the line when it has a number.
  defp first_speaks(%{"act" => act} = first) when is_integer(act) do
    place = Enum.join([Edition.roman(act) | List.wrap(first["scene"])], ".")
    Enum.join([place | List.wrap(first["line"])], ", ")
  end

  defp first_speaks(_first), do: "—"

  defp main_forms(forms) do
    forms
    |> Map.delete("unmarked")
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.take(2)
    |> Enum.map_join(" · ", &PlayLabels.verse_form_label(elem(&1, 0)))
  end

  defp presence(assigns) do
    presence = assigns.data["presence"] || %{}

    rows =
      Enum.map(assigns.data["characters"] || [], fn c ->
        {c["name"], Map.new(c["columns"], fn [i, n] -> {i, n} end)}
      end)

    columns = presence["columns"] || []

    assigns =
      assign(assigns, basis: presence["basis"], columns: columns, rows: rows)

    ~H"""
    <.panel
      :if={@columns != [] and @rows != []}
      id="presence"
      title={gettext("Who shares the stage")}
      lede={basis_note(@basis, length(@columns))}
    >
      <div
        class="overflow-x-auto"
        tabindex="0"
        role="region"
        aria-label={gettext("Who shares the stage")}
      >
        <table class="stat-matrix border-separate border-spacing-0">
          <thead>
            <tr>
              <th><span class="sr-only">{gettext("Character")}</span></th>
              <th
                :for={{column, i} <- Enum.with_index(@columns)}
                scope="col"
                title={column_title(column, @range)}
                class={["p-0.5", act_start(@columns, i)]}
              >
                <i
                  :if={column["form"]}
                  class={["mx-auto block h-1 w-[1.1rem] rounded-sm", form_colour(column["form"])]}
                >
                </i>
                <span class="sr-only">{column_title(column, @range)}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{name, cells} <- @rows}>
              <th
                scope="row"
                class="whitespace-nowrap pr-3 text-left font-serif text-sm font-semibold"
              >
                <PlayText.inline_content text={name} />
              </th>
              <td
                :for={{column, i} <- Enum.with_index(@columns)}
                class={["c p-0.5", cells[i] && "on", act_start(@columns, i)]}
                title={cells[i] && cell_title(name, column, @range, cells[i])}
              >
                <span :if={cells[i]} class="sr-only">
                  {ngettext("%{count} line", "%{count} lines", cells[i])}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </.panel>
    """
  end

  defp basis_note("scene", _n),
    do: gettext("A filled cell means the character speaks in that scene.")

  defp basis_note("passage", n),
    do:
      gettext(
        "This play encodes no scenes, so the columns are its %{n} metrical passages. A filled cell means the character speaks in that passage.",
        n: n
      )

  defp basis_note(_basis, _n),
    do: gettext("A filled cell means the character speaks in that division.")

  defp column_title(%{"form" => form} = column, range),
    do: "#{PlayLabels.verse_form_label(form)}#{verses_range(column, range)}"

  defp column_title(%{"act" => act, "label" => label}, _range) when is_integer(act),
    do: "#{Edition.roman(act)}: #{InlineMarkup.plain(label)}"

  defp column_title(%{"label" => label}, _range), do: InlineMarkup.plain(label)

  defp cell_title(name, column, range, n),
    do:
      "#{InlineMarkup.plain(name)} · #{column_title(column, range)} · " <>
        ngettext("%{count} line", "%{count} lines", n)

  defp act_start(columns, i),
    do:
      if(i > 0 and Enum.at(columns, i - 1)["act"] != Enum.at(columns, i)["act"],
        do: "pl-2.5"
      )

  # A passage whose verses carry no number (a song) has no range to name.
  defp verses_range(%{"from" => nil}, _label), do: ""
  defp verses_range(passage, label), do: " · #{label} #{range(passage)}"

  defp range(%{"from" => from, "to" => to}) when from == to, do: "#{from}"
  defp range(%{"from" => from, "to" => to}), do: "#{from}–#{to}"

  defp percent(part, total), do: "#{round(part / max(total, 1) * 100)}%"
end
