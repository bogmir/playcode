defmodule PlaycodeWeb.PlayCatalogueLive do
  @moduledoc """
  /plays: the published plays, each original with its translations beneath, searchable,
  25 to a page. Drafts are left out.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Play Catalogue"))
     |> assign(:plays, [])
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:total_pages, 1)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_page(params["page"])

    total = Catalogue.count_plays_grouped(search: search)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)

    plays = Catalogue.list_plays_grouped(search: search, page: page, per_page: @per_page)

    {:noreply,
     socket
     |> assign(:plays, plays)
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = if search == "", do: [], else: [search: search]
    {:noreply, push_patch(socket, to: ~p"/plays?#{params}")}
  end

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(s) do
      {n, ""} -> max(1, n)
      _ -> 1
    end
  end

  defp page_params("", page), do: [page: page]
  defp page_params(search, page), do: [search: search, page: page]

  defp relationship_label("traduccion"), do: gettext("translation")
  defp relationship_label("adaptacion"), do: gettext("adaptation")
  defp relationship_label("refundicion"), do: gettext("refundición")
  defp relationship_label(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold text-base-content mb-2">{gettext("Play Catalogue")}</h1>
      <p class="text-base-content/70 mb-8">
        {gettext(
          "Early modern European theatre (16th–17th century) from the EMOTHE and ARTELOPE collections"
        )}
      </p>

      <form id="catalogue-search" phx-change="search" phx-submit="search" class="mb-8">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search by title, author, or code...")}
          phx-debounce="300"
          class="input input-bordered w-full md:max-w-md"
        />
      </form>

      <div class="grid gap-3">
        <div :for={play <- @plays}>
          <%!-- Main play --%>
          <div class="rounded-box border border-base-300 bg-base-100 px-5 py-3.5 hover:shadow-md transition-shadow">
            <div class="flex items-center gap-3">
              <.link navigate={~p"/plays/#{play.code}"} class="flex-1 min-w-0">
                <span class="font-semibold text-base-content hover:text-primary transition-colors">
                  {play.title}
                </span>
                <span :if={play.author_name} class="text-sm text-base-content/60 ml-2">
                  {play.author_name}
                </span>
              </.link>
              <.link
                :if={play.derived_plays != []}
                navigate={~p"/plays/#{play.code}/compare"}
                class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
                data-tip={gettext("Compare")}
              >
                <.icon name="hero-arrows-right-left-mini" class="size-3.5" />
              </.link>
              <.export_buttons play={play} />
            </div>
          </div>
          <%!-- Derived plays (translations, adaptations, etc.) --%>
          <div
            :for={derived <- play.derived_plays}
            class="ml-6 mt-1 flex items-center gap-2 rounded-box border border-base-300/60 bg-base-200/30 px-4 py-2.5"
          >
            <span class="text-base-content/30 text-xs">└</span>
            <.link navigate={~p"/plays/#{derived.code}"} class="flex-1 min-w-0">
              <span class="text-sm text-base-content hover:text-primary transition-colors">
                {derived.title}
              </span>
              <span :if={derived.author_name} class="text-xs text-base-content/50 ml-2">
                {derived.author_name}
              </span>
            </.link>
            <span
              :if={relationship_label(derived.relationship_type)}
              class="badge badge-ghost badge-xs"
            >
              {relationship_label(derived.relationship_type)}
            </span>
            <.export_buttons play={derived} />
          </div>
        </div>

        <p :if={@plays == []} class="text-base-content/50 text-center py-12">
          {gettext("No plays found. Try a different search term.")}
        </p>
      </div>

      <%!-- Pagination --%>
      <div :if={@total_pages > 1} class="mt-6 flex items-center justify-center gap-4">
        <.link
          :if={@page > 1}
          patch={~p"/plays?#{page_params(@search, @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" />{gettext("Previous")}
        </.link>
        <span class="text-sm text-base-content/60">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={~p"/plays?#{page_params(@search, @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Next")}<.icon name="hero-chevron-right-mini" class="size-4" />
        </.link>
      </div>
    </div>
    """
  end

  defp export_buttons(assigns) do
    ~H"""
    <div class="flex items-center border-l border-base-200 pl-2 ml-1 gap-0.5">
      <a
        href={~p"/export/#{@play.id}/tei"}
        rel="nofollow"
        download
        class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
        data-tip="TEI-XML"
      >
        <.icon name="hero-code-bracket-mini" class="size-3.5" />
      </a>
      <a
        href={~p"/export/#{@play.id}/html"}
        rel="nofollow"
        download
        class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
        data-tip="HTML"
      >
        <.icon name="hero-globe-alt-mini" class="size-3.5" />
      </a>
      <a
        href={~p"/export/#{@play.id}/pdf"}
        rel="nofollow"
        download
        class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
        data-tip="PDF"
      >
        <.icon name="hero-document-arrow-down-mini" class="size-3.5" />
      </a>
      <a
        href={~p"/export/#{@play.id}/epub"}
        rel="nofollow"
        download
        class="btn btn-xs btn-ghost btn-square text-base-content/50 hover:text-primary tooltip tooltip-bottom"
        data-tip="EPUB"
      >
        <.icon name="hero-book-open-mini" class="size-3.5" />
      </a>
    </div>
    """
  end
end
