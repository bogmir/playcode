defmodule PlaycodeWeb.Admin.ContentEditor.Structure do
  @moduledoc """
  The content editor's Structure tab: the play's outline, its paratexts and divisions in one
  order (`Playcode.Outline`), and the form that adds or edits a division, its notes included.
  """

  use PlaycodeWeb, :html

  import PlaycodeWeb.Admin.ContentEditor.Components

  alias Playcode.Catalogue.Paratext
  alias Playcode.Outline
  alias PlaycodeWeb.Components.PlayText
  alias PlaycodeWeb.PlayLabels

  attr :paratexts, :list, required: true
  attr :divisions, :list, required: true
  attr :removals, :map, required: true
  attr :selected_division_id, :string, default: nil

  def tab(assigns) do
    ~H"""
    <div class="animate-in fade-in">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
        <h2 class="text-lg font-semibold text-base-content">{gettext("Play Structure")}</h2>
        <div class="flex gap-2">
          <button phx-click="new_paratext" class="btn btn-sm btn-ghost btn-outline gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add paratext")}
          </button>
          <button phx-click="new_division" class="btn btn-sm btn-primary gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add division")}
          </button>
        </div>
      </div>
      <p class="mb-4 text-sm text-base-content/70">
        {gettext(
          "Everything in the play in the order it is read, as the file and every page give it. A new item stands last: drag it into place."
        )}
      </p>
      <div
        :if={@divisions == [] and @paratexts == []}
        class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/70"
      >
        <.icon name="hero-bars-3-bottom-left" class="mx-auto mb-2 size-8 text-base-content/70" />
        <p>{gettext("No acts or scenes yet. Add an act to get started.")}</p>
      </div>
      <.drag_sort_list id="outline" data-event="reorder_outline" class="space-y-3">
        <div
          :for={item <- Outline.items(@paratexts, @divisions)}
          id={"outline-" <> String.replace(Outline.key(item), ":", "-")}
          data-id={Outline.key(item)}
          class="drag-item rounded-box border border-base-300 bg-base-100 shadow-sm overflow-hidden"
        >
          <.outline_row
            item={item}
            removals={@removals}
            selected_division_id={@selected_division_id}
          />
        </div>
      </.drag_sort_list>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :removals, :map, required: true
  attr :selected_division_id, :string, default: nil

  # One item of the outline: a paratext, or a division with its scenes and lists nested.
  defp outline_row(%{item: %Paratext{}} = assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 px-4 py-3">
      <div class="flex min-w-0 items-center gap-2">
        <.drag_handle />
        <span class="badge badge-outline badge-sm">{PlayLabels.kind_label(@item.kind)}</span>
        <span class="truncate text-sm font-medium">{PlayLabels.paratext_title(@item)}</span>
      </div>
      <div class="flex shrink-0 gap-1">
        <button
          phx-click="edit_paratext"
          phx-value-id={@item.id}
          class="btn btn-ghost btn-xs tooltip"
          aria-label={gettext("Edit")}
          data-tip={gettext("Edit")}
        >
          <.icon name="hero-pencil-square-mini" class="size-4" />
        </button>
        <button
          phx-click="delete_paratext"
          phx-value-id={@item.id}
          data-confirm={gettext("Delete this paratext?")}
          class="btn btn-ghost btn-xs text-error tooltip"
          aria-label={gettext("Delete")}
          data-tip={gettext("Delete")}
        >
          <.icon name="hero-trash-mini" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  defp outline_row(assigns) do
    ~H"""
    <div
      id={"division-#{@item.id}"}
      class="flex items-center justify-between gap-2 px-4 py-3 bg-base-200/30"
    >
      <div class="flex min-w-0 items-center gap-2">
        <.drag_handle />
        <.icon
          name={if @item.type == "elenco", do: "hero-users-mini", else: "hero-folder-mini"}
          class="size-4 text-base-content/70"
        />
        <span class="truncate font-semibold">
          <PlayText.inline_content text={division_label(@item)} />
        </span>
        <span class="badge badge-ghost badge-sm">
          {@item.type}{if @item.number, do: " #{@item.number}"}
        </span>
      </div>
      <div class="flex shrink-0 items-center gap-1">
        <button
          :if={@item.type != "elenco"}
          phx-click="new_division"
          phx-value-parent-id={@item.id}
          class="btn btn-xs btn-ghost gap-1"
        >
          <.icon name="hero-plus-mini" class="size-3" /> {gettext("Add subdivision")}
        </button>
        <button
          :if={@item.type != "elenco"}
          phx-click="select_division_auto"
          phx-value-id={@item.id}
          class="btn btn-xs btn-ghost btn-outline gap-1"
        >
          <.icon name="hero-pencil-square-mini" class="size-3" /> {gettext("Edit Content")}
        </button>
        <.division_actions division={@item} confirm={delete_confirm(@item, @removals)} />
      </div>
    </div>
    <.drag_sort_list
      :if={@item.type != "elenco"}
      id={"children-#{@item.id}"}
      data-event="reorder_children"
      data-parent={@item.id}
      class="divide-y divide-base-300/50"
    >
      <div
        :for={child <- @item.children}
        id={"division-#{child.id}"}
        data-id={child.id}
        class="drag-item flex items-center justify-between gap-2 px-4 py-2 pl-8 transition-colors hover:bg-base-200/30"
      >
        <div class="flex min-w-0 items-center gap-2">
          <.drag_handle />
          <span :if={child.type == "elenco"} class="flex items-center gap-2 text-sm">
            <.icon name="hero-users-mini" class="size-3.5" />
            <PlayText.inline_content text={division_label(child)} />
          </span>
          <button
            :if={child.type != "elenco"}
            phx-click="select_division"
            phx-value-id={child.id}
            class={[
              "flex items-center gap-2 text-sm transition-colors",
              if(@selected_division_id == child.id,
                do: "font-bold text-primary",
                else: "text-base-content/70 hover:text-base-content"
              )
            ]}
          >
            <.icon name="hero-document-mini" class="size-3.5" />
            <PlayText.inline_content text={division_label(child)} />
            <span :if={@selected_division_id == child.id} class="badge badge-primary badge-sm ml-1">
              {gettext("editing")}
            </span>
          </button>
        </div>
        <.division_actions division={child} confirm={delete_confirm(child, @removals)} />
      </div>
    </.drag_sort_list>
    """
  end

  attr :division, :map, required: true
  attr :confirm, :string, required: true

  defp division_actions(assigns) do
    ~H"""
    <div class="flex shrink-0 gap-1">
      <button
        phx-click="edit_division"
        phx-value-id={@division.id}
        class="btn btn-ghost btn-xs tooltip"
        aria-label={gettext("Edit metadata")}
        data-tip={gettext("Edit metadata")}
      >
        <.icon name="hero-cog-6-tooth-mini" class="size-4" />
      </button>
      <button
        phx-click="delete_division"
        phx-value-id={@division.id}
        data-confirm={@confirm}
        class="btn btn-ghost btn-xs text-error tooltip"
        aria-label={gettext("Delete")}
        data-tip={gettext("Delete")}
      >
        <.icon name="hero-trash-mini" class="size-4" />
      </button>
    </div>
    """
  end

  # A deletion's confirmation, with the characters listed nowhere else that go with it.
  defp delete_confirm(%{type: "elenco"} = list, removals) do
    case Map.get(removals, list.id, 0) do
      0 ->
        gettext("Delete this cast list?")

      n ->
        ngettext(
          "Delete this cast list? One character listed nowhere else goes with it.",
          "Delete this cast list? %{count} characters listed nowhere else go with it.",
          n
        )
    end
  end

  defp delete_confirm(%{parent_id: nil} = division, removals) do
    case Map.get(removals, division.id, 0) do
      0 ->
        gettext("Delete this division and all its content?")

      n ->
        ngettext(
          "Delete this division and all its content? One character listed nowhere else goes with it.",
          "Delete this division and all its content? %{count} characters listed nowhere else go with it.",
          n
        )
    end
  end

  defp delete_confirm(_scene, _removals), do: gettext("Delete this scene and all its content?")

  attr :form, Phoenix.HTML.Form, required: true
  attr :editing, :any, default: nil, doc: "the division being edited, nil for a new one"
  attr :subdivision, :any, default: nil, doc: "a new or edited division's parent, if any"
  attr :play_id, :string, required: true
  attr :user, :any, required: true

  def modal(assigns) do
    ~H"""
    <h3 id="content-modal-title" class="text-lg font-bold mb-4">
      {editing_label(@editing)} {gettext("Division")}
    </h3>
    <.form
      id="division-form"
      for={@form}
      as={:division}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label" for={@form[:type].id}>
          <span class="label-text font-medium">{gettext("Type")} *</span>
        </label>
        <.input
          field={@form[:type]}
          type="select"
          options={division_types(@subdivision, @editing && @editing.type)}
        />
      </div>
      <div>
        <label class="label" for={@form[:number].id}>
          <span class="label-text font-medium">{gettext("Number")}</span>
        </label>
        <.input field={@form[:number]} type="number" />
      </div>
      <div>
        <label class="label" for={@form[:title].id}>
          <span class="label-text font-medium">{gettext("Title")}</span>
        </label>
        <.input field={@form[:title]} type="text" placeholder={gettext("e.g. ACTO PRIMERO")} />
      </div>
      <div :if={@form[:type].value == "elenco"}>
        <label class="label" for={@form[:intro].id}>
          <span class="label-text font-medium">{gettext("Before the list")}</span>
        </label>
        <.input field={@form[:intro]} type="textarea" rows="2" />
      </div>
      <div :if={@form[:type].value == "elenco"}>
        <label class="label" for={@form[:note].id}>
          <span class="label-text font-medium">{gettext("Note after the list")}</span>
        </label>
        <.input field={@form[:note]} type="textarea" rows="4" />
        <p class="text-xs text-base-content/70 mt-1">
          {gettext("A blank line starts a new paragraph; <<…>> marks italics.")}
        </p>
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    <.live_component
      :if={@editing}
      module={PlaycodeWeb.Admin.NotesComponent}
      id={"notes-#{@editing.id}"}
      anchor={@editing}
      play_id={@play_id}
      user={@user}
    />
    """
  end

  # The types a division may take at its level: an act's children are its scenes and cast
  # lists. A type a file gave that is not among them stays offered, so an edit keeps it.
  defp division_types(subdivision?, current) do
    types =
      if subdivision?,
        do: [{gettext("Scene (escena)"), "escena"}, {gettext("Scene (scene)"), "scene"}],
        else: [
          {gettext("Act (acto)"), "acto"},
          {gettext("Act (act)"), "act"},
          {gettext("Jornada"), "jornada"},
          {gettext("Prologue"), "prologo"},
          {gettext("Argument"), "argumento"},
          {gettext("Epilogue"), "epilogue"}
        ]

    types = types ++ [{gettext("Cast list"), "elenco"}]

    if current in [nil, ""] or List.keymember?(types, current, 1),
      do: types,
      else: types ++ [{current, current}]
  end
end
