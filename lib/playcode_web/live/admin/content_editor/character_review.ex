defmodule PlaycodeWeb.Admin.ContentEditor.CharacterReview do
  @moduledoc """
  The content editor's Character Review tab: the play's speeches, filtered by speaker label
  and assignment, with the bulk actions that assign characters and set labels.
  """

  use PlaycodeWeb, :html

  alias PlaycodeWeb.Admin.PlayContentEditorLive

  attr :characters, :list, required: true
  attr :speeches, :list, required: true
  attr :speaker_labels, :list, required: true
  attr :selected_speeches, :any, required: true
  attr :cr_selected_character_ids, :list, required: true
  attr :filter_label, :string, default: nil
  attr :filter_assigned, :any, default: nil
  attr :first_child_contents, :map, required: true
  attr :cr_display_limit, :integer, default: 50

  def tab(assigns) do
    all_filtered = PlayContentEditorLive.cr_filtered_speeches(assigns)
    total = length(all_filtered)
    limited = Enum.take(all_filtered, assigns.cr_display_limit)
    assigns = assign(assigns, visible_speeches: limited, total_filtered: total)

    selected_chars =
      Enum.filter(assigns.characters, &(&1.id in assigns.cr_selected_character_ids))
      |> Enum.sort_by(fn c ->
        Enum.find_index(assigns.cr_selected_character_ids, &(&1 == c.id))
      end)

    available_chars =
      Enum.reject(assigns.characters, &(&1.id in assigns.cr_selected_character_ids))

    assigns = assign(assigns, selected_chars: selected_chars, available_chars: available_chars)

    ~H"""
    <div class="animate-in fade-in">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold text-base-content">{gettext("Character Review")}</h2>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext(
              "Assign characters to speeches. Create characters from speaker labels found in the text."
            )}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-4">
        <div class="lg:col-span-1">
          <div class="rounded-box border border-base-300 bg-base-100 shadow-sm">
            <div class="border-b border-base-300 px-4 py-3">
              <h3 id="cr-characters-heading" class="font-semibold text-sm">
                {gettext("Characters")} ({length(@characters)})
              </h3>
            </div>
            <%!-- Focusable: nothing inside it is, so the keyboard could not scroll it. --%>
            <div
              class="divide-y divide-base-200 max-h-96 overflow-y-auto"
              role="region"
              tabindex="0"
              aria-labelledby="cr-characters-heading"
            >
              <div :for={char <- @characters} class="px-4 py-2 text-sm">
                <span class="font-medium">{char.name}</span>
                <span class="text-base-content/70 text-xs ml-1">{char.xml_id}</span>
              </div>
              <div :if={@characters == []} class="px-4 py-6 text-sm text-base-content/70 text-center">
                {gettext("No characters yet.")}
              </div>
            </div>
          </div>
        </div>

        <div class="lg:col-span-3">
          <div class="mb-4 flex flex-wrap items-center gap-3">
            <form phx-change="cr_filter" class="flex items-center gap-2 flex-1">
              <select
                name="label"
                class="select select-bordered select-sm"
                aria-label={gettext("Filter by speaker")}
              >
                <option value="">{gettext("All speakers")}</option>
                <option value="__none__" selected={@filter_label == :none}>
                  {gettext("(No label)")}
                </option>
                <option
                  :for={label <- @speaker_labels}
                  :if={label && label != ""}
                  value={label}
                  selected={@filter_label == label}
                >
                  {label}
                </option>
              </select>
              <select
                name="assigned"
                class="select select-bordered select-sm"
                aria-label={gettext("Filter by assignment")}
              >
                <option value="">{gettext("All")}</option>
                <option value="yes" selected={@filter_assigned == true}>{gettext("Assigned")}</option>
                <option value="no" selected={@filter_assigned == false}>
                  {gettext("Unassigned")}
                </option>
              </select>
            </form>
            <div class="flex items-center gap-1">
              <button phx-click="cr_select_all_visible" class="btn btn-ghost btn-xs">
                {gettext("Select all")}
              </button>
              <button phx-click="cr_deselect_all" class="btn btn-ghost btn-xs">
                {gettext("Deselect")}
              </button>
            </div>
          </div>

          <div
            :if={MapSet.size(@selected_speeches) > 0}
            class="mb-4 rounded-box border border-primary/30 bg-primary/5 p-4 space-y-3"
          >
            <span class="text-sm font-semibold">
              {gettext("%{count} selected", count: MapSet.size(@selected_speeches))}
            </span>

            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm text-base-content/70">{gettext("Characters:")}</span>
              <span
                :for={char <- @selected_chars}
                class="badge badge-sm badge-primary gap-1"
              >
                {char.name}
                <button
                  type="button"
                  phx-click="cr_remove_character"
                  phx-value-id={char.id}
                  class="hover:text-primary-content/60"
                  aria-label={gettext("Remove %{name}", name: char.name)}
                >
                  <.icon name="hero-x-mark-mini" class="size-3" />
                </button>
              </span>
              <span :if={@selected_chars == []} class="text-sm text-base-content/70 italic">
                {gettext("none")}
              </span>
              <form :if={@available_chars != []} phx-change="cr_add_character" class="inline">
                <select
                  name="character_id"
                  class="select select-bordered select-xs"
                  aria-label={gettext("Add character")}
                >
                  <option value="">{gettext("Add...")}</option>
                  <option :for={char <- @available_chars} value={char.id}>
                    {char.name}
                  </option>
                </select>
              </form>
              <form phx-submit="cr_assign_characters" class="inline">
                <button type="submit" class="btn btn-primary btn-xs">
                  {gettext("Assign Characters")}
                </button>
              </form>
            </div>

            <div class="divider my-0 h-0"></div>

            <form phx-submit="cr_set_label" class="flex flex-wrap items-center gap-2">
              <label for="cr-speaker-label" class="text-sm text-base-content/70">
                {gettext("Label:")}
              </label>
              <input
                id="cr-speaker-label"
                type="text"
                name="speaker_label"
                placeholder={gettext("Leave empty to clear")}
                class="input input-bordered input-xs w-40"
              />
              <button type="submit" class="btn btn-outline btn-xs">
                {gettext("Set Label")}
              </button>
              <button
                type="button"
                phx-click="cr_clear_label"
                class="btn btn-ghost btn-xs tooltip"
                data-tip={gettext("Clear label")}
              >
                <.icon name="hero-x-mark-mini" class="size-3.5" />
                {gettext("Clear")}
              </button>
            </form>
          </div>

          <div class="rounded-box border border-base-300 bg-base-100 shadow-sm divide-y divide-base-200">
            <div
              :for={speech <- @visible_speeches}
              class={[
                "flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-base-200/50",
                MapSet.member?(@selected_speeches, speech.id) && "bg-primary/5"
              ]}
              phx-click="cr_toggle_speech"
              phx-value-id={speech.id}
            >
              <input
                type="checkbox"
                class="checkbox checkbox-sm checkbox-primary"
                checked={MapSet.member?(@selected_speeches, speech.id)}
                aria-labelledby={"cr-speaker-#{speech.id} cr-first-#{speech.id}"}
                readonly
              />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span id={"cr-speaker-#{speech.id}"} class="font-medium text-sm">
                    {speech.speaker_label || gettext("(no speaker)")}
                  </span>
                  <span :if={speech.division} class="text-xs text-base-content/70">
                    {speech.division.title || speech.division.type}
                  </span>
                </div>
                <p
                  :if={@first_child_contents[speech.id]}
                  id={"cr-first-#{speech.id}"}
                  class="text-xs text-base-content/70 truncate mt-0.5"
                >
                  {@first_child_contents[speech.id]}
                </p>
              </div>
              <div class="flex-shrink-0 flex gap-1 flex-wrap items-center">
                <span
                  :for={char <- Playcode.PlayContent.Element.characters(speech)}
                  class="badge badge-sm badge-outline badge-success"
                >
                  {char.name}
                </span>
                <span
                  :if={speech.element_characters == []}
                  class="badge badge-sm badge-ghost"
                >
                  {gettext("unassigned")}
                </span>
                <button
                  phx-click="cr_go_to_speech"
                  phx-value-id={speech.id}
                  class="btn btn-ghost btn-xs btn-square ml-1 tooltip"
                  data-tip={gettext("View in content")}
                  title={gettext("View in content")}
                >
                  <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
                </button>
              </div>
            </div>
            <div
              :if={@visible_speeches == []}
              class="px-4 py-8 text-center text-sm text-base-content/70"
            >
              {gettext("No speeches found.")}
            </div>
          </div>
          <div
            :if={length(@visible_speeches) < @total_filtered}
            class="mt-2 text-center"
          >
            <button phx-click="cr_show_more" class="btn btn-ghost btn-sm">
              {gettext("Show more (%{remaining} remaining)",
                remaining: @total_filtered - length(@visible_speeches)
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
