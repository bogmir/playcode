defmodule PlaycodeWeb.Admin.ContentEditor.Characters do
  @moduledoc """
  The content editor's Cast list tab: each cast list and its entries, and the forms that add
  a character, edit an entry (and the character it names), or add an existing character.
  """

  use PlaycodeWeb, :html

  import PlaycodeWeb.Admin.ContentEditor.Components

  alias Playcode.PlayContent.{Character, InlineMarkup}
  alias PlaycodeWeb.Components.PlayText

  attr :characters, :list, required: true
  attr :cast_lists, :list, required: true
  attr :divisions, :list, required: true
  attr :original_pairs, :map, default: nil, doc: "each character's original, in a translation"

  def tab(assigns) do
    ~H"""
    <div class="animate-in fade-in">
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-lg font-semibold text-base-content">
          {gettext("Cast list")}
          <span class="text-base-content/70 font-normal">({length(@characters)})</span>
        </h2>
        <%!-- With a list, each section has its own. --%>
        <button
          :if={@cast_lists == []}
          phx-click="new_character"
          class="btn btn-sm btn-primary gap-1"
        >
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add Character")}
        </button>
      </div>
      <p class="mb-4 text-sm text-base-content/70">
        {gettext(
          "Each cast list of the play, in the order it is read. Drag a line within its list or into another; a character is named as its first line names it."
        )}
      </p>
      <div
        :if={@cast_lists == []}
        class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/70"
      >
        <.icon name="hero-user-group" class="mx-auto mb-2 size-8 text-base-content/70" />
        <p>{gettext("No characters yet. Add one to get started.")}</p>
      </div>
      <.drag_sort_list
        :if={@cast_lists != []}
        id="cast-lists"
        class="rounded-box border border-base-300 bg-base-100 shadow-sm"
        data-event="reorder_entries"
      >
        <%= for list <- @cast_lists do %>
          <div
            id={"list-#{list.id}"}
            data-id={"list:#{list.id}"}
            class="drag-item flex flex-wrap items-center justify-between gap-2 border-b border-base-300 bg-base-200/50 px-3 py-2"
          >
            <div class="min-w-0 text-sm">
              <span :if={act = list_act(@divisions, list)} class="text-base-content/70">
                <PlayText.inline_content text={division_label(act)} /> ·
              </span>
              <span class="font-semibold">{list.title || gettext("Cast list")}</span>
            </div>
            <div class="flex flex-wrap gap-1">
              <button
                phx-click="new_character"
                phx-value-list-id={list.id}
                class="btn btn-ghost btn-xs gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Add character")}
              </button>
              <button
                phx-click="add_existing_entry"
                phx-value-list-id={list.id}
                class="btn btn-ghost btn-xs gap-1"
              >
                <.icon name="hero-user-plus-mini" class="size-3" />
                {gettext("Add an existing character")}
              </button>
              <button
                phx-click="edit_division"
                phx-value-id={list.id}
                class="btn btn-ghost btn-xs tooltip"
                aria-label={gettext("Edit header")}
                data-tip={gettext("Edit header")}
              >
                <.icon name="hero-pencil-square-mini" class="size-4" />
              </button>
            </div>
          </div>
          <div
            :for={entry <- list.entries}
            id={"entry-#{entry.id}"}
            data-id={"entry:#{entry.id}"}
            class="drag-item flex items-center gap-2 border-b border-base-300/60 px-3 py-2.5 last:border-b-0 hover:bg-base-200/40"
          >
            <.drag_handle />
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="font-medium text-sm">{entry.name}</span>
                <span :if={entry.character} class="text-xs text-base-content/70 font-mono">
                  {entry.character.xml_id}
                </span>
                <span :if={!entry.character} class="badge badge-ghost badge-sm">
                  {gettext("Names no character")}
                </span>
                <span :if={entry.group_heading} class="badge badge-outline badge-sm">
                  {entry.group_heading}
                </span>
                <span
                  :if={entry.character && entry.character.is_hidden}
                  class="badge badge-ghost badge-sm"
                >
                  {gettext("hidden")}
                </span>
                <.original_pair
                  :if={entry.character && Map.has_key?(@original_pairs || %{}, entry.character.id)}
                  id={"pair-#{entry.id}"}
                  character={entry.character}
                  original={@original_pairs[entry.character.id]}
                />
              </div>
              <p :if={entry.description} class="text-xs text-base-content/70 truncate">
                {entry.description}
              </p>
              <p
                :if={entry.character && entry.character.actor}
                class="text-xs text-base-content/70 truncate"
              >
                {gettext("Actor")}: {entry.character.actor}
              </p>
            </div>
            <div class="flex shrink-0 gap-0.5">
              <button
                phx-click="edit_entry"
                phx-value-id={entry.id}
                class="btn btn-ghost btn-xs tooltip"
                aria-label={gettext("Edit")}
                data-tip={gettext("Edit")}
              >
                <.icon name="hero-pencil-square-mini" class="size-3.5" />
              </button>
              <button
                phx-click="delete_entry"
                phx-value-id={entry.id}
                data-confirm={gettext("Remove this line from the list?")}
                class="btn btn-ghost btn-xs text-error tooltip"
                aria-label={gettext("Remove")}
                data-tip={gettext("Remove")}
              >
                <.icon name="hero-trash-mini" class="size-3.5" />
              </button>
            </div>
          </div>
        <% end %>
      </.drag_sort_list>
    </div>
    """
  end

  # The act a cast list stands in, or nil for one before, between or after the acts.
  defp list_act(_divisions, %{parent_id: nil}), do: nil
  defp list_act(divisions, list), do: Enum.find(divisions, &(&1.id == list.parent_id))

  attr :id, :string, required: true
  attr :character, Character, required: true
  attr :original, Character, default: nil

  defp original_pair(assigns) do
    ~H"""
    <span id={@id} class="text-xs text-base-content/70">
      <%= cond do %>
        <% @original -> %>
          {gettext("Original:")}
          <span class="font-medium text-base-content">{InlineMarkup.plain(@original.name)}</span>
          <span :if={@original.xml_id == @character.original_xml_id} class="badge badge-info badge-sm">
            {gettext("corrected")}
          </span>
        <% @character.no_original -> %>
          {gettext("No original")}
          <span class="badge badge-info badge-sm">{gettext("corrected")}</span>
        <% true -> %>
          <span class="badge badge-warning badge-sm">{gettext("No original found")}</span>
      <% end %>
    </span>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :editing, :any, default: nil, doc: "the character being edited, nil for a new one"

  def character_modal(assigns) do
    ~H"""
    <h3 id="content-modal-title" class="text-lg font-bold mb-4">
      {editing_label(@editing)} {gettext("Character")}
    </h3>
    <.form
      id="character-form"
      for={@form}
      as={:character}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label" for={@form[:xml_id].id}>
          <span class="label-text font-medium">XML ID *</span>
        </label>
        <.input field={@form[:xml_id]} type="text" required placeholder={gettext("e.g. DONA_ANA")} />
      </div>
      <div>
        <label class="label" for={@form[:name].id}>
          <span class="label-text font-medium">{gettext("Name")} *</span>
        </label>
        <.input field={@form[:name]} type="text" required placeholder={gettext("e.g. Dona Ana")} />
      </div>
      <div>
        <label class="label" for={@form[:description].id}>
          <span class="label-text font-medium">{gettext("Description")}</span>
        </label>
        <.input field={@form[:description]} type="text" placeholder={gettext("e.g. una dama")} />
      </div>
      <div>
        <label class="label" for={@form[:actor].id}>
          <span class="label-text font-medium">{gettext("Actor in the original cast")}</span>
        </label>
        <.input field={@form[:actor]} type="text" placeholder={gettext("e.g. Mr. Betterton")} />
      </div>
      <div>
        <.input field={@form[:is_hidden]} type="checkbox" label={gettext("Hidden character")} />
      </div>
      <div>
        <.input field={@form[:is_group]} type="checkbox" label={gettext("A group speaking as one")} />
      </div>
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :character_form, :any, default: nil, doc: "the character an edited entry names"

  attr :original_choice, :map,
    default: nil,
    doc: "its original character's choices, in a translation"

  def entry_modal(assigns) do
    ~H"""
    <h3 id="content-modal-title" class="text-lg font-bold mb-4">
      {gettext("Edit")} {gettext("Character")}
    </h3>
    <.form
      id="entry-form"
      for={@form}
      as={:entry}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <p class="text-sm text-base-content/70">
        {gettext("As this list gives the character. Another list may name it otherwise.")}
      </p>
      <div>
        <label class="label" for={@form[:name].id}>
          <span class="label-text font-medium">{gettext("Name")} *</span>
        </label>
        <.input field={@form[:name]} type="text" required />
      </div>
      <div>
        <label class="label" for={@form[:description].id}>
          <span class="label-text font-medium">{gettext("Description")}</span>
        </label>
        <.input field={@form[:description]} type="text" placeholder={gettext("e.g. una dama")} />
      </div>
      <div>
        <label class="label" for={@form[:group_heading].id}>
          <span class="label-text font-medium">{gettext("Group")}</span>
        </label>
        <.input field={@form[:group_heading]} type="text" placeholder={gettext("e.g. Criados")} />
      </div>
      <fieldset :if={@character_form} class="space-y-4 border-t border-base-300 pt-4">
        <legend class="text-sm font-medium">{gettext("In every list")}</legend>
        <div>
          <label class="label" for={@character_form[:xml_id].id}>
            <span class="label-text font-medium">XML ID *</span>
          </label>
          <.input field={@character_form[:xml_id]} type="text" required />
        </div>
        <div>
          <label class="label" for={@character_form[:actor].id}>
            <span class="label-text font-medium">{gettext("Actor in the original cast")}</span>
          </label>
          <.input
            field={@character_form[:actor]}
            type="text"
            placeholder={gettext("e.g. Mr. Betterton")}
          />
        </div>
        <div :if={@original_choice}>
          <.input
            field={@character_form[:original]}
            type="select"
            label={gettext("Original character")}
            options={@original_choice.options}
            value={@character_form[:original].value || @original_choice.selected}
          />
        </div>
        <div>
          <.input
            field={@character_form[:is_hidden]}
            type="checkbox"
            label={gettext("Hidden character")}
          />
        </div>
        <div>
          <.input
            field={@character_form[:is_group]}
            type="checkbox"
            label={gettext("A group speaking as one")}
          />
        </div>
      </fieldset>
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :existing_options, :list, default: []

  def existing_entry_modal(assigns) do
    ~H"""
    <h3 id="content-modal-title" class="text-lg font-bold mb-4">
      {gettext("Add an existing character")}
    </h3>
    <p :if={@existing_options == []} class="text-sm text-base-content/70">
      {gettext("Every character is in this list already.")}
    </p>
    <.form
      :if={@existing_options != []}
      id="existing-entry-form"
      for={@form}
      as={:existing}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label" for={@form[:character_id].id}>
          <span class="label-text font-medium">{gettext("Character")} *</span>
        </label>
        <.input field={@form[:character_id]} type="select" options={@existing_options} />
      </div>
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Add")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    """
  end
end
