defmodule PlaycodeWeb.Admin.ContentEditor.Content do
  @moduledoc """
  The content editor's Content tab: a division's elements, the search across the play's text,
  and the form that adds or edits an element, its notes included.
  """

  use PlaycodeWeb, :html

  import PlaycodeWeb.Admin.ContentEditor.Components

  alias PlaycodeWeb.PlayLabels

  attr :content_search, :string, required: true
  attr :content_search_results, :list, required: true
  attr :selected_division_id, :string, default: nil
  attr :divisions, :list, required: true
  attr :elements, :list, required: true
  attr :selected_elements, :any, required: true
  attr :characters, :list, required: true
  attr :inline_editing_id, :string, default: nil

  def tab(assigns) do
    ~H"""
    <div
      id="content-tab"
      phx-hook=".ScrollToElement"
      class="animate-in fade-in"
    >
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToElement">
        export default {
          mounted() {
            this.handleEvent("scroll-to-element", ({id}) => {
              requestAnimationFrame(() => {
                const el = document.getElementById(id)
                if (el) el.scrollIntoView({behavior: "smooth", block: "center"})
              })
            })
          }
        }
      </script>
      <%!-- Search bar --%>
      <div class="mb-4">
        <form phx-change="content_search" phx-submit="content_search">
          <div class="relative">
            <.icon
              name="hero-magnifying-glass-mini"
              class="absolute left-3 top-2.5 size-4 text-base-content/70 pointer-events-none"
            />
            <input
              type="text"
              name="query"
              value={@content_search}
              placeholder={gettext("Search text across all scenes...")}
              phx-debounce="300"
              class="input input-bordered input-sm w-full pl-9"
              autocomplete="off"
            />
            <button
              :if={@content_search != ""}
              type="button"
              phx-click="content_search_clear"
              class="absolute right-2 top-1.5 btn btn-ghost btn-xs btn-circle"
              aria-label={gettext("Clear search")}
            >
              <.icon name="hero-x-mark-mini" class="size-3.5" />
            </button>
          </div>
        </form>
      </div>

      <%!-- Search results --%>
      <div :if={@content_search != ""} class="mb-4">
        <p class="text-xs text-base-content/70 mb-2">
          {ngettext(
            "1 result",
            "%{count} results",
            length(@content_search_results),
            count: length(@content_search_results)
          )}
        </p>
        <div
          class="rounded-box border border-base-300 bg-base-100 shadow-sm divide-y divide-base-200 max-h-64 overflow-y-auto"
          tabindex="0"
          role="region"
          aria-label={gettext("Search results")}
        >
          <div
            :for={result <- @content_search_results}
            class="px-4 py-2 cursor-pointer hover:bg-base-200/50"
            phx-click="content_search_go"
            phx-value-id={result.id}
            phx-value-division-id={result.division_id}
            phx-value-parent-id={result.parent_id || ""}
          >
            <div class="flex items-center gap-2">
              <span class="badge badge-sm badge-outline">
                {element_type_label(result.type)}
              </span>
              <span :if={result.speaker_label} class="text-xs font-medium">
                {result.speaker_label}
              </span>
              <span :if={result.division} class="text-xs text-base-content/70">
                {result.division.title || result.division.type}
              </span>
            </div>
            <p class="text-sm text-base-content/70 truncate mt-0.5">
              {String.slice(result.content || result.speaker_label || "", 0..120)}
            </p>
          </div>
          <div
            :if={@content_search_results == []}
            class="px-4 py-6 text-center text-sm text-base-content/70"
          >
            {gettext("No results found.")}
          </div>
        </div>
      </div>

      <%!-- No division selected --%>
      <div
        :if={!@selected_division_id}
        class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-12 text-center"
      >
        <.icon name="hero-cursor-arrow-rays" class="mx-auto mb-3 size-10 text-base-content/70" />
        <p class="text-base-content/70 mb-3">
          {gettext("Select a scene or act from the Structure tab to edit its content.")}
        </p>
        <button
          phx-click="switch_tab"
          phx-value-tab="structure"
          class="btn btn-sm btn-outline gap-1"
        >
          <.icon name="hero-bars-3-bottom-left-mini" class="size-4" /> {gettext("Go to Structure")}
        </button>
      </div>

      <%!-- Division selected --%>
      <div :if={@selected_division_id}>
        <%!-- Content header with division selector --%>
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div class="flex flex-col gap-1">
            <div
              :if={parent_division_label(@divisions, @selected_division_id)}
              class="flex items-center gap-1.5 text-sm text-base-content/70"
            >
              <.icon name="hero-folder-mini" class="size-3.5" />
              <span>{parent_division_label(@divisions, @selected_division_id)}</span>
              <.icon name="hero-chevron-right-mini" class="size-3" />
            </div>
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold text-base-content">
                {current_division_label(@divisions, @selected_division_id)}
              </h2>
              <%!-- Quick division navigation --%>
              <div class="flex gap-1">
                <button
                  :if={prev_division_id(@divisions, @selected_division_id)}
                  phx-click="select_division"
                  phx-value-id={prev_division_id(@divisions, @selected_division_id)}
                  class="btn btn-ghost btn-xs tooltip"
                  aria-label={gettext("Previous")}
                  data-tip={gettext("Previous")}
                >
                  <.icon name="hero-chevron-left-mini" class="size-4" />
                </button>
                <button
                  :if={next_division_id(@divisions, @selected_division_id)}
                  phx-click="select_division"
                  phx-value-id={next_division_id(@divisions, @selected_division_id)}
                  class="btn btn-ghost btn-xs tooltip"
                  aria-label={gettext("Next")}
                  data-tip={gettext("Next")}
                >
                  <.icon name="hero-chevron-right-mini" class="size-4" />
                </button>
              </div>
            </div>
          </div>
          <div class="flex gap-1">
            <button
              phx-click="new_element"
              phx-value-type="speech"
              class="btn btn-xs btn-primary gap-1"
            >
              <.icon name="hero-plus-mini" class="size-3" /> {gettext("Speech")}
            </button>
            <button
              phx-click="new_element"
              phx-value-type="stage_direction"
              class="btn btn-xs btn-outline gap-1"
            >
              <.icon name="hero-plus-mini" class="size-3" /> {gettext("Stage Dir.")}
            </button>
            <button
              phx-click="new_element"
              phx-value-type="prose"
              class="btn btn-xs btn-outline gap-1"
            >
              <.icon name="hero-plus-mini" class="size-3" /> {gettext("Prose")}
            </button>
          </div>
        </div>

        <div
          :if={@elements == []}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/70"
        >
          <.icon name="hero-document-text" class="mx-auto mb-2 size-8 text-base-content/70" />
          <p>{gettext("No content yet. Add a speech, stage direction, or prose.")}</p>
        </div>

        <div :if={@elements != []} class="flex items-center gap-2 mb-2">
          <button phx-click="el_select_all" class="btn btn-ghost btn-xs">
            {gettext("Select all")}
          </button>
          <button
            :if={MapSet.size(@selected_elements) > 0}
            phx-click="el_deselect_all"
            class="btn btn-ghost btn-xs"
          >
            {gettext("Deselect")}
          </button>
        </div>

        <div
          :if={MapSet.size(@selected_elements) > 0}
          class="mb-3 flex items-center gap-3 rounded-box border border-error/30 bg-error/5 p-3"
        >
          <span class="text-sm font-medium">
            {gettext("%{count} selected", count: MapSet.size(@selected_elements))}
          </span>
          <button
            phx-click="el_delete_selected"
            data-confirm={
              gettext("Delete %{count} elements and their children?",
                count: MapSet.size(@selected_elements)
              )
            }
            class="btn btn-error btn-sm"
          >
            <.icon name="hero-trash-mini" class="size-4" />
            {gettext("Delete selected")}
          </button>
          <button phx-click="el_deselect_all" class="btn btn-ghost btn-sm">
            {gettext("Cancel")}
          </button>
        </div>

        <div :if={@elements != []} class="space-y-2">
          <.element_card
            :for={element <- @elements}
            element={element}
            characters={@characters}
            depth={0}
            selected_elements={@selected_elements}
            inline_editing_id={@inline_editing_id}
          />
        </div>
      </div>
    </div>
    """
  end

  defp parent_division_label(divisions, id) do
    Enum.find_value(divisions, nil, fn div ->
      Enum.find_value(div.children || [], nil, fn child ->
        if child.id == id, do: division_label(div)
      end)
    end)
  end

  defp current_division_label(divisions, id) do
    Enum.find_value(divisions, "Unknown", fn div ->
      if div.id == id do
        division_label(div)
      else
        Enum.find_value(div.children || [], nil, fn child ->
          if child.id == id, do: division_label(child)
        end)
      end
    end)
  end

  defp all_leaf_divisions(divisions) do
    Enum.flat_map(divisions, fn div ->
      case div.children do
        [] -> [div.id]
        children -> Enum.map(children, & &1.id)
      end
    end)
  end

  defp prev_division_id(divisions, current_id) do
    leaves = all_leaf_divisions(divisions)
    idx = Enum.find_index(leaves, &(&1 == current_id))

    if idx && idx > 0, do: Enum.at(leaves, idx - 1)
  end

  defp next_division_id(divisions, current_id) do
    leaves = all_leaf_divisions(divisions)
    idx = Enum.find_index(leaves, &(&1 == current_id))

    if idx && idx < length(leaves) - 1, do: Enum.at(leaves, idx + 1)
  end

  attr :element, :map, required: true
  attr :characters, :list, required: true
  attr :depth, :integer, default: 0
  attr :selected_elements, :any, default: MapSet.new()
  attr :inline_editing_id, :string, default: nil

  defp element_card(assigns) do
    assigns = assign(assigns, :is_inline_editing, assigns.inline_editing_id == assigns.element.id)

    ~H"""
    <div
      id={"element-#{@element.id}"}
      class={[
        "rounded-box border border-base-300 bg-base-100 shadow-sm",
        @depth > 0 && "ml-4 mt-1",
        @depth == 0 && MapSet.member?(@selected_elements, @element.id) && "ring-2 ring-primary/30"
      ]}
    >
      <div class="flex items-center justify-between p-3">
        <div class="flex items-center flex-1 min-w-0">
          <input
            :if={@depth == 0}
            id={"el-chk-#{@element.id}"}
            phx-hook="ShiftClick"
            data-id={@element.id}
            type="checkbox"
            class="checkbox checkbox-sm checkbox-primary mr-2 shrink-0"
            checked={MapSet.member?(@selected_elements, @element.id)}
            aria-labelledby={"el-type-#{@element.id} el-speaker-#{@element.id} el-text-#{@element.id}"}
          />
          <span id={"el-type-#{@element.id}"} class="badge badge-sm badge-outline mr-2 shrink-0">
            {element_type_label(@element.type)}
          </span>
          <%!-- Speaker label: click opens modal --%>
          <span
            :if={@element.speaker_label}
            id={"el-speaker-#{@element.id}"}
            phx-click="edit_element"
            phx-value-id={@element.id}
            class="font-medium cursor-pointer hover:text-primary shrink-0"
          >
            {@element.speaker_label}
          </span>
          <%!-- Content: inline editing or click to edit --%>
          <%!-- A browser strips the newlines from the one-line quick edit: a text with a
            line break opens in the form instead. --%>
          <span
            :if={@element.content && !@is_inline_editing}
            id={"el-text-#{@element.id}"}
            phx-click={
              if String.contains?(@element.content, "\n"), do: "edit_element", else: "inline_edit"
            }
            phx-value-id={@element.id}
            class="text-sm text-base-content/80 cursor-pointer hover:text-base-content truncate"
            title={@element.content}
          >
            {String.slice(@element.content || "", 0..80)}{if String.length(@element.content || "") >
                                                               80,
                                                             do: "..."}
          </span>
          <form
            :if={@is_inline_editing}
            id={"inline-edit-#{@element.id}"}
            phx-hook=".InlineEdit"
            phx-submit="inline_save"
            class="flex-1 min-w-0 ml-1"
          >
            <input type="hidden" name="element_id" value={@element.id} />
            <input
              type="text"
              name="value"
              value={@element.content || ""}
              class="input input-sm input-bordered w-full"
              aria-label={element_type_label(@element.type)}
              phx-key="Escape"
              phx-keydown="inline_cancel"
            />
          </form>
          <span :if={@element.verse_type} class="text-xs text-base-content/70 ml-2">
            ({@element.verse_type})
          </span>
          <span :if={@element.line_number} class="text-xs text-base-content/70 ml-1">
            L{@element.line_number}
          </span>
          <span :if={@element.is_aside} class="badge badge-ghost badge-sm ml-1">
            {gettext("aside")}
          </span>
        </div>
        <div class="flex gap-1">
          <%!-- Insert Above for top-level elements (speeches, stage dirs, prose) --%>
          <div :if={@depth == 0} class="dropdown dropdown-end">
            <label
              tabindex="0"
              role="button"
              class="btn btn-xs btn-ghost btn-outline tooltip"
              aria-label={gettext("Insert Above")}
              data-tip={gettext("Insert Above")}
            >
              <.icon name="hero-arrow-up-mini" class="size-4" />
            </label>
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-1 shadow bg-base-100 rounded-box w-40"
            >
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="speech"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Speech")}
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="stage_direction"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Stage Direction")}
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="prose"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Prose")}
                </button>
              </li>
            </ul>
          </div>
          <%!-- Insert Above for verse lines inside line groups --%>
          <button
            :if={@element.type == "verse_line" && @element.parent_id}
            phx-click="new_element_before"
            phx-value-type="verse_line"
            phx-value-position={@element.position}
            phx-value-parent-id={@element.parent_id}
            class="btn btn-xs btn-ghost btn-outline tooltip"
            aria-label={gettext("Insert Above")}
            data-tip={gettext("Insert Above")}
          >
            <.icon name="hero-arrow-up-mini" class="size-4" />
          </button>
          <button
            phx-click="edit_element"
            phx-value-id={@element.id}
            class="btn btn-ghost btn-xs tooltip"
            aria-label={gettext("Edit")}
            data-tip={gettext("Edit")}
          >
            <.icon name="hero-pencil-square-mini" class="size-4" />
          </button>
          <button
            phx-click="delete_element"
            phx-value-id={@element.id}
            data-confirm={gettext("Delete this element and its children?")}
            class="btn btn-ghost btn-xs text-error tooltip"
            aria-label={gettext("Delete")}
            data-tip={gettext("Delete")}
          >
            <.icon name="hero-trash-mini" class="size-4" />
          </button>
        </div>
      </div>
      <%!-- Children --%>
      <div
        :if={match?([_ | _], Map.get(@element, :children, []))}
        class="border-t border-base-300 bg-base-200/30 px-3 py-2"
      >
        <.element_card
          :for={child <- @element.children}
          element={child}
          characters={@characters}
          depth={@depth + 1}
          selected_elements={@selected_elements}
          inline_editing_id={@inline_editing_id}
        />
      </div>
      <%!-- Add child buttons --%>
      <div :if={@element.type == "speech"} class="border-t border-base-300 px-3 py-2">
        <button
          phx-click="new_element"
          phx-value-type="line_group"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Line Group")}
        </button>
        <button
          phx-click="new_element"
          phx-value-type="stage_direction"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Stage Direction")}
        </button>
        <button
          phx-click="new_element"
          phx-value-type="prose"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Prose")}
        </button>
      </div>
      <div :if={@element.type == "line_group"} class="border-t border-base-300 px-3 py-2">
        <button
          phx-click="new_element"
          phx-value-type="verse_line"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Verse Line")}
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".InlineEdit">
        export default {
          mounted() {
            this._cancelled = false
            const input = this.el.querySelector("input[name='value']")
            if (input) {
              input.focus()
              input.select()
              input.addEventListener("keydown", (e) => {
                if (e.key === "Escape") {
                  this._cancelled = true
                }
              })
              input.addEventListener("blur", () => {
                if (!this._cancelled) {
                  this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}))
                }
              })
            }
          }
        }
      </script>
    </div>
    """
  end

  defp element_type_label("speech"), do: gettext("Speech")
  defp element_type_label("stage_direction"), do: gettext("Stage Dir.")
  defp element_type_label("verse_line"), do: gettext("Verse")
  defp element_type_label("prose"), do: gettext("Prose")
  defp element_type_label("line_group"), do: gettext("Line Group")
  defp element_type_label(type), do: type

  attr :form, Phoenix.HTML.Form, required: true
  attr :editing, :any, default: nil, doc: "the element being edited, nil for a new one"
  attr :characters, :list, required: true
  attr :modal_element_type, :string, required: true
  attr :editing_character_ids, :list, default: []
  attr :play_id, :string, required: true
  attr :user, :any, required: true

  attr :manual_numbers, :boolean,
    default: false,
    doc: "the play is Manual: its numbers are typed, not counted by its rule"

  def modal(assigns) do
    ~H"""
    <h3 id="content-modal-title" class="text-lg font-bold mb-4">
      {editing_label(@editing)} {element_type_label(@modal_element_type)}
    </h3>
    <.form
      id="element-form"
      for={@form}
      as={:element}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <.input field={@form[:type]} type="hidden" />
      <.input field={@form[:position]} type="hidden" />
      <.input field={@form[:parent_id]} type="hidden" />

      <%!-- Speech fields --%>
      <div :if={@modal_element_type == "speech"}>
        <div class="mb-4">
          <label class="label" for={@form[:speaker_label].id}>
            <span class="label-text font-medium">{gettext("Speaker Label")}</span>
          </label>
          <.input field={@form[:speaker_label]} type="text" placeholder={gettext("e.g. ANA")} />
          <p class="mt-1 text-xs text-base-content/70">
            {gettext("Words only the Folio prints: <folio>…</folio>")}
          </p>
        </div>
        <div class="mb-4">
          <label class="label">
            <span class="label-text font-medium">{gettext("Characters")}</span>
          </label>
          <% selected_chars = Enum.filter(@characters, &(&1.id in @editing_character_ids))
          available_chars = Enum.reject(@characters, &(&1.id in @editing_character_ids)) %>
          <input
            :for={cid <- @editing_character_ids}
            type="hidden"
            name="character_ids[]"
            value={cid}
          />
          <div class="flex flex-wrap gap-1 mb-2">
            <span
              :for={char <- selected_chars}
              class="badge badge-sm badge-primary gap-1"
            >
              {char.name}
              <button
                type="button"
                phx-click="el_remove_character"
                phx-value-id={char.id}
                class="hover:text-primary-content/60"
                aria-label={gettext("Remove %{name}", name: char.name)}
              >
                <.icon name="hero-x-mark-mini" class="size-3" />
              </button>
            </span>
            <span :if={selected_chars == []} class="text-sm text-base-content/70 italic">
              {gettext("none")}
            </span>
          </div>
          <select
            :if={available_chars != []}
            id="el-char-select"
            phx-hook=".ElCharSelect"
            class="select select-bordered select-sm w-full"
            aria-label={gettext("Add character")}
          >
            <option value="">{gettext("Add character...")}</option>
            <option :for={char <- available_chars} value={char.id}>
              {char.name} ({char.xml_id})
            </option>
          </select>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".ElCharSelect">
            export default {
              mounted() {
                this.el.addEventListener("change", () => {
                  if (this.el.value) {
                    this.pushEvent("el_add_character", {character_id: this.el.value})
                  }
                })
              }
            }
          </script>
          <div :if={@characters == []} class="text-sm text-base-content/70 text-center py-2">
            {gettext("No characters defined.")}
          </div>
        </div>
        <div>
          <.input field={@form[:is_aside]} type="checkbox" label={gettext("Aside")} />
        </div>
      </div>

      <%!-- Stage direction fields --%>
      <div :if={@modal_element_type == "stage_direction"}>
        <div class="mb-4">
          <label class="label" for={@form[:content].id}>
            <span class="label-text font-medium">{gettext("Content")}</span>
          </label>
          <.input
            field={@form[:content]}
            type="textarea"
            rows="3"
            placeholder={gettext("Stage direction text...")}
          />
          <p class="mt-1 text-xs text-base-content/70">
            {gettext("Words only the Folio prints: <folio>…</folio>")}
          </p>
          <p class="mt-1 text-xs text-base-content/70">
            {gettext(
              "A tagged name, place or prop: <rs type=\"atrezzo\">…</rs>; its kind one of %{kinds}",
              kinds: Enum.join(PlayLabels.tag_types(), ", ")
            )}
          </p>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="label" for={@form[:stage_type].id}>
              <span class="label-text font-medium">{gettext("Kind")}</span>
            </label>
            <.input
              field={@form[:stage_type]}
              type="select"
              options={PlayLabels.stage_type_options(@editing && @editing.stage_type)}
            />
          </div>
          <div>
            <label class="label" for={@form[:rend].id}>
              <span class="label-text font-medium">Rend</span>
            </label>
            <.input field={@form[:rend]} type="text" placeholder={gettext("e.g. italics")} />
          </div>
        </div>
      </div>

      <%!-- Prose fields --%>
      <div :if={@modal_element_type == "prose"}>
        <label class="label" for={@form[:content].id}>
          <span class="label-text font-medium">{gettext("Content")}</span>
        </label>
        <.input
          field={@form[:content]}
          type="textarea"
          rows="4"
          placeholder={gettext("Prose text...")}
        />
        <p class="mt-1 text-xs text-base-content/70">
          {gettext("Stage direction in the text: <stage type=\"delivery\">…</stage>")}
        </p>
        <p class="mt-1 text-xs text-base-content/70">
          {gettext("Words spoken aside: <aside>…</aside>")}
        </p>
        <.input
          field={@form[:aside_continues]}
          type="checkbox"
          label={gettext("Continues the aside before it")}
        />
        <p class="mt-1 text-xs text-base-content/70">
          {gettext("Words only the Folio prints: <folio>…</folio>")}
        </p>
        <p class="mt-1 text-xs text-base-content/70">
          {gettext(
            "A tagged name, place or prop: <rs type=\"atrezzo\">…</rs>; its kind one of %{kinds}",
            kinds: Enum.join(PlayLabels.tag_types(), ", ")
          )}
        </p>
        <p class="mt-1 text-xs text-base-content/70">
          {gettext("Number of a printed line in the text: <lb n=\"1320\"/>")}
        </p>
      </div>

      <%!-- Line group fields --%>
      <div :if={@modal_element_type == "line_group"}>
        <label class="label" for={@form[:verse_type].id}>
          <span class="label-text font-medium">{gettext("Verse Type")}</span>
        </label>
        <.input field={@form[:verse_type]} type="select" options={verse_types()} />
        <label class="label mt-4" for={@form[:content].id}>
          <span class="label-text font-medium">{gettext("Heading")}</span>
        </label>
        <.input field={@form[:content]} type="text" placeholder={gettext("A Song")} />
        <p class="mt-1 text-xs text-base-content/70">
          {gettext("Printed before the stanza's lines, as a song's title is; blank for none.")}
        </p>
      </div>

      <%!-- Verse line fields --%>
      <div :if={@modal_element_type == "verse_line"}>
        <div class="mb-4">
          <label class="label" for={@form[:content].id}>
            <span class="label-text font-medium">{gettext("Content")} *</span>
          </label>
          <.input
            field={@form[:content]}
            type="text"
            required
            placeholder={gettext("Verse line text...")}
          />
          <p class="mt-1 text-xs text-base-content/70">
            {gettext("Stage direction in the text: <stage type=\"delivery\">…</stage>")}
          </p>
          <p class="mt-1 text-xs text-base-content/70">
            {gettext("Words spoken aside: <aside>…</aside>")}
          </p>
          <.input
            field={@form[:aside_continues]}
            type="checkbox"
            label={gettext("Continues the aside before it")}
          />
          <p class="mt-1 text-xs text-base-content/70">
            {gettext("Words only the Folio prints: <folio>…</folio>")}
          </p>
          <p class="mt-1 text-xs text-base-content/70">
            {gettext(
              "A tagged name, place or prop: <rs type=\"atrezzo\">…</rs>; its kind one of %{kinds}",
              kinds: Enum.join(PlayLabels.tag_types(), ", ")
            )}
          </p>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <%!-- A play not Manual is numbered by its rule on every save: a typed number would go. --%>
          <div :if={@manual_numbers}>
            <label class="label" for={@form[:line_number].id}>
              <span class="label-text font-medium">{gettext("Line Number")}</span>
            </label>
            <.input field={@form[:line_number]} type="text" />
          </div>
          <div>
            <label class="label" for={@form[:part].id}>
              <span class="label-text font-medium">{gettext("Part (split line)")}</span>
            </label>
            <.input field={@form[:part]} type="select" options={part_options()} />
          </div>
        </div>
      </div>

      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    <.live_component
      :if={@editing && @editing.type in ~w(verse_line prose stage_direction trailer speech)}
      module={PlaycodeWeb.Admin.NotesComponent}
      id={"notes-#{@editing.id}"}
      anchor={@editing}
      play_id={@play_id}
      user={@user}
    />
    """
  end

  defp verse_types do
    [
      {"", ""},
      {"Redondilla", "redondilla"},
      {"Romance", "romance"},
      {"Romance tirada", "romance_tirada"},
      {"Octava real", "octava_real"},
      {"Soneto", "soneto"},
      {"Decima", "decima"},
      {"Terceto", "terceto"},
      {"Silva", "silva"},
      {"Quintilla", "quintilla"},
      {"Lira", "lira"},
      {"Cancion", "cancion"},
      {"Free", "free"},
      {"Otro", "otro"}
    ]
  end

  defp part_options do
    [
      {"(none)", ""},
      {"I - Inicio", "I"},
      {"M - Medio", "M"},
      {"F - Final", "F"}
    ]
  end
end
