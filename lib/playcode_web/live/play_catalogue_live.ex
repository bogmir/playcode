defmodule PlaycodeWeb.PlayCatalogueLive do
  @moduledoc """
  /plays: the published plays, each original with its translations beneath, searchable and
  filtered by language, form and kind as the static site's catalogue is, 25 groups to a
  page. Drafts are left out.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias PlaycodeWeb.PlayLabels

  @per_page 25
  @filters ~w(language form kind)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Play Catalogue"))}
  end

  # ponytail: every published play is read and grouped in memory, a few hundred rows; a
  # query per facet if the corpus grows by an order of magnitude.
  @impl true
  def handle_params(params, _url, socket) do
    chosen =
      for key <- ["search" | @filters], present?(params[key]), into: %{}, do: {key, params[key]}

    plays = Catalogue.list_plays(complete: true)
    searched = Enum.filter(plays, &found?(&1, chosen["search"]))
    shown = Enum.filter(searched, &chosen?(&1, chosen))
    groups = groups(plays, MapSet.new(shown, & &1.id))
    total_pages = max(1, ceil(length(groups) / @per_page))
    page = min(parse_page(params["page"]), total_pages)

    {:noreply,
     assign(socket,
       chosen: chosen,
       search: chosen["search"] || "",
       facets: facets(searched),
       shown: length(shown),
       groups: groups |> Enum.drop((page - 1) * @per_page) |> Enum.take(@per_page),
       page: page,
       total_pages: total_pages
     )}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, patch(socket, Map.put(socket.assigns.chosen, "search", search))}
  end

  def handle_event("filter", params, socket) do
    {:noreply, patch(socket, Map.merge(socket.assigns.chosen, Map.take(params, @filters)))}
  end

  defp patch(socket, chosen) do
    params = for {key, value} <- chosen, present?(value), do: {key, value}
    push_patch(socket, to: ~p"/plays?#{params}")
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp found?(_play, nil), do: true

  defp found?(play, search) do
    term = String.downcase(search)

    Enum.any?(
      [play.title, play.author_name, play.code],
      &(&1 && String.contains?(String.downcase(&1), term))
    )
  end

  defp chosen?(play, chosen),
    do: Enum.all?(@filters, &(chosen[&1] in [nil, value(play, &1)]))

  defp value(play, "language"), do: play.language
  defp value(play, "form"), do: Play.form(play)
  defp value(play, "kind"), do: play.relationship_type || "original"

  # Each original with its published translations beneath, shown when any of them is; a
  # translation whose original is not published stands on its own.
  defp groups(plays, shown) do
    published = MapSet.new(plays, & &1.id)
    {roots, derived} = Enum.split_with(plays, &(&1.parent_play_id not in published))
    beneath = Enum.group_by(derived, & &1.parent_play_id)

    for root <- Enum.sort_by(roots, &sort_key/1),
        members = Enum.sort_by(Map.get(beneath, root.id, []), &sort_key/1),
        Enum.any?([root | members], &(&1.id in shown)),
        do: {root, members}
  end

  defp sort_key(play), do: {play.title_sort || play.title, play.title}

  defp facets(plays) do
    [
      {"language", gettext("Language"), &Play.language_name/1},
      {"form", gettext("Form"), &PlayLabels.form_label/1},
      {"kind", gettext("Kind"), &kind_label/1}
    ]
    |> Enum.map(fn {key, legend, label} ->
      options =
        plays
        |> Enum.frequencies_by(&value(&1, key))
        |> Enum.reject(fn {value, _} -> is_nil(value) end)
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.map(fn {value, count} -> {value, label.(value), count} end)

      {key, legend, options}
    end)
  end

  defp kind_label("original"), do: gettext("Originals")
  defp kind_label("traduccion"), do: gettext("Translations")
  defp kind_label("adaptacion"), do: gettext("Adaptations")
  defp kind_label("version"), do: gettext("Versions")

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(s) do
      {n, ""} -> max(1, n)
      _ -> 1
    end
  end

  defp page_path(chosen, page),
    do: ~p"/plays?#{Enum.to_list(chosen) ++ [{"page", page}]}"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-8 lg:grid lg:grid-cols-[13rem_minmax(0,1fr)] lg:gap-10">
      <div id="catalogue-filters-panel" class="fold mb-6 lg:mb-0">
        <button
          type="button"
          phx-click={JS.toggle_class("flipped", to: "#catalogue-filters-panel")}
          class="btn btn-outline btn-sm lg:hidden"
        >
          <.icon name="hero-funnel-mini" class="size-4" />{gettext("Filters")}
        </button>
        <form
          id="catalogue-filters"
          phx-change="filter"
          class="fold-body mt-3 space-y-5 text-sm lg:mt-1"
        >
          <fieldset :for={{key, legend, options} <- @facets}>
            <legend class="mb-1.5 text-xs font-semibold uppercase tracking-wider text-base-content/70">
              {legend}
            </legend>
            <label class="flex cursor-pointer items-center gap-2 py-0.5">
              <input
                type="radio"
                name={key}
                value=""
                checked={!@chosen[key]}
                class="radio radio-xs radio-primary"
              />
              <span class="flex-1">{gettext("All")}</span>
            </label>
            <label
              :for={{value, label, count} <- options}
              class="flex cursor-pointer items-center gap-2 py-0.5"
            >
              <input
                type="radio"
                name={key}
                value={value}
                checked={@chosen[key] == value}
                class="radio radio-xs radio-primary"
              />
              <span class="flex-1">{label}</span>
              <span class="tabular-nums text-base-content/70">{count}</span>
            </label>
          </fieldset>
        </form>
      </div>

      <div class="min-w-0">
        <h1 class="mb-2 font-serif text-3xl font-semibold text-base-content">
          {gettext("Play Catalogue")}
        </h1>
        <p class="mb-6 max-w-2xl font-serif text-lg text-base-content/80">
          {gettext(
            "Early modern European theatre (16th–17th century) from the EMOTHE and ARTELOPE collections"
          )}
        </p>

        <form id="catalogue-search" phx-change="search" phx-submit="search" class="mb-3">
          <input
            type="text"
            name="search"
            value={@search}
            placeholder={gettext("Search by title, author, or code...")}
            aria-label={gettext("Search by title, author, or code...")}
            phx-debounce="300"
            class="input input-bordered w-full"
          />
        </form>
        <p id="catalogue-count" aria-live="polite" class="mb-4 text-sm text-base-content/70">
          {ngettext("%{count} play", "%{count} plays", @shown)}
        </p>

        <ol class="divide-y divide-base-300 border-y border-base-300">
          <li :for={{play, derived} <- @groups} class="py-3">
            <.entry play={play} compare={derived != []} />
            <ul :if={derived != []} class="mt-1.5 space-y-1.5 border-l border-base-300 pl-4">
              <li :for={translation <- derived}>
                <.entry play={translation} />
              </li>
            </ul>
          </li>
        </ol>
        <p :if={@groups == []} class="py-12 text-center text-base-content/70">
          {gettext("No plays found. Try a different search term.")}
        </p>

        <div :if={@total_pages > 1} class="mt-6 flex items-center justify-center gap-4">
          <.link :if={@page > 1} patch={page_path(@chosen, @page - 1)} class="btn btn-sm btn-ghost">
            <.icon name="hero-chevron-left-mini" class="size-4" />{gettext("Previous")}
          </.link>
          <span class="text-sm text-base-content/70">
            {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
          </span>
          <.link
            :if={@page < @total_pages}
            patch={page_path(@chosen, @page + 1)}
            class="btn btn-sm btn-ghost"
          >
            {gettext("Next")}<.icon name="hero-chevron-right-mini" class="size-4" />
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :play, Play, required: true
  attr :compare, :boolean, default: false

  # One play's line; on a phone its downloads go under the title.
  defp entry(assigns) do
    ~H"""
    <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
      <.link navigate={~p"/plays/#{@play.code}"} class="min-w-0 flex-1 basis-60">
        <span class="font-serif text-lg font-semibold text-base-content hover:text-primary">
          {@play.title}
        </span>
        <span :if={@play.relationship_type} class="ml-1 text-xs text-base-content/70">
          {@play.relationship_type |> PlayLabels.relationship_type_label() |> String.downcase()}
        </span>
        <span :if={@play.author_name} class="block text-sm text-base-content/70">
          {@play.author_name}
        </span>
      </.link>
      <div class="flex flex-wrap items-center gap-1">
        <.link
          :if={@compare}
          navigate={~p"/plays/#{@play.code}/compare"}
          class="btn btn-ghost btn-xs"
        >
          <.icon name="hero-arrows-right-left-mini" class="size-3.5" />{gettext("Compare")}
        </.link>
        <.download_group base={"/export/#{@play.id}"} rel="nofollow" download />
      </div>
    </div>
    """
  end
end
