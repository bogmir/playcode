defmodule PlaycodeWeb.Admin.PlacePicker do
  @moduledoc """
  The place picker of a play's admin tabs: the place chosen, or a search over the gazetteer's
  names in any language, with its suggestions below. The gazetteer is corpus-global, so a
  `<select>` of every place stops being usable long before the corpus is fully imported.

  Only the markup is shared. The page keeps `picked`, `term` and `suggestions` in its socket
  and answers three events: `search_places` (`%{"term" => term}`, from the search form),
  `pick_place` (`%{"id" => id}`, from a suggestion) and `clear_pick`.
  """

  use PlaycodeWeb, :html

  alias Playcode.Places

  attr :id, :string, required: true, doc: "the search form's id; its input's is `<id>-term`"
  attr :picked, :any, required: true, doc: "the chosen `Places.Place`, or nil"
  attr :term, :string, required: true
  attr :suggestions, :list, required: true
  attr :gazetteer, :map, required: true

  def place_picker(assigns) do
    ~H"""
    <div class="relative grow">
      <%!-- Picked state: the place is chosen. --%>
      <div
        :if={@picked}
        class="input input-bordered input-sm flex h-auto min-h-8 items-center justify-between gap-2"
      >
        <span class="truncate text-sm">{Places.breadcrumb(@picked, @gazetteer, "es")}</span>
        <button
          type="button"
          phx-click="clear_pick"
          class="btn btn-circle btn-ghost btn-xs shrink-0"
          title={gettext("Clear")}
        >
          <.icon name="hero-x-mark-mini" class="size-3.5" />
        </button>
      </div>
      <%!-- Search state: names in any language, so Istanbul finds Constantinopla. --%>
      <form :if={is_nil(@picked)} id={@id} phx-change="search_places" phx-submit="search_places">
        <input
          type="text"
          id={"#{@id}-term"}
          name="term"
          value={@term}
          phx-debounce="200"
          placeholder={gettext("Search any name, in any language")}
          class="input input-bordered input-sm w-full"
          autocomplete="off"
        />
      </form>
      <ul
        :if={@suggestions != []}
        class="rounded-box absolute z-20 mt-1 max-h-64 w-full overflow-y-auto border border-base-300 bg-base-100 shadow-lg"
      >
        <li :for={place <- @suggestions}>
          <button
            type="button"
            phx-click="pick_place"
            phx-value-id={place.id}
            class="w-full px-3 py-2 text-left transition-colors hover:bg-base-200"
          >
            <div class="truncate text-sm font-medium">{Places.display_name(place, "es")}</div>
            <div class="mt-0.5 truncate text-xs text-base-content/70">
              {Places.breadcrumb(place, @gazetteer, "es")}
            </div>
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
