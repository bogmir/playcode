defmodule PlaycodeWeb.Admin.ContentEditor.Paratexts do
  @moduledoc """
  The content editor's Paratexts tab: the play's paratexts, and the form that adds or edits one.
  """

  use PlaycodeWeb, :html

  import PlaycodeWeb.Admin.ContentEditor.Components

  alias PlaycodeWeb.PlayLabels

  attr :paratexts, :list, required: true

  def tab(assigns) do
    ~H"""
    <div class="animate-in fade-in">
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-lg font-semibold text-base-content">
          {gettext("Paratexts")}
          <span class="text-base-content/70 font-normal">({length(@paratexts)})</span>
        </h2>
        <button phx-click="new_paratext" class="btn btn-sm btn-primary gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add Paratext")}
        </button>
      </div>
      <p class="mb-4 text-sm text-base-content/70">
        {gettext(
          "Texts around the play's text: dedications, editor's introductions, prologues, arguments, the scene of the action."
        )}
      </p>
      <div
        :if={@paratexts == []}
        class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/70"
      >
        <.icon name="hero-document-text" class="mx-auto mb-2 size-8 text-base-content/70" />
        <p>{gettext("No paratexts yet.")}</p>
      </div>
      <div id="paratext-list" class="space-y-3">
        <div
          :for={paratext <- @paratexts}
          id={"paratext-#{paratext.id}"}
          class="rounded-box border border-base-300 bg-base-100 shadow-sm"
        >
          <div class="flex items-start justify-between gap-4 p-4">
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2 mb-1">
                <span class="badge badge-outline badge-sm">
                  {PlayLabels.kind_label(paratext.kind)}
                </span>
                <span :if={paratext.heading} class="font-medium text-sm">{paratext.heading}</span>
              </div>
              <p class="text-sm text-base-content/70 line-clamp-3 whitespace-pre-line">
                {paratext.content}
              </p>
            </div>
          </div>
          <div class="flex justify-end gap-1 border-t border-base-300 px-3 py-2">
            <button
              phx-click="edit_paratext"
              phx-value-id={paratext.id}
              class="btn btn-ghost btn-xs gap-1"
            >
              <.icon name="hero-pencil-square-micro" class="size-3.5" /> {gettext("Edit")}
            </button>
            <button
              phx-click="delete_paratext"
              phx-value-id={paratext.id}
              data-confirm={gettext("Delete this paratext?")}
              class="btn btn-ghost btn-xs text-error gap-1"
            >
              <.icon name="hero-trash-micro" class="size-3.5" /> {gettext("Delete")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :editing, :any, default: nil, doc: "the paratext being edited, nil for a new one"

  def modal(assigns) do
    ~H"""
    <h3 id="content-modal-title" class="text-lg font-bold mb-4">
      {editing_label(@editing)} {gettext("Paratext")}
    </h3>
    <.form
      id="paratext-form"
      for={@form}
      as={:paratext}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label" for={@form[:kind].id}>
          <span class="label-text font-medium">{gettext("Kind")} *</span>
        </label>
        <.input
          field={@form[:kind]}
          type="select"
          options={PlayLabels.kind_options(@editing && @editing.kind)}
        />
      </div>
      <div>
        <label class="label" for={@form[:heading].id}>
          <span class="label-text font-medium">{gettext("Heading")}</span>
        </label>
        <.input
          field={@form[:heading]}
          type="text"
          placeholder={gettext("Optional heading")}
        />
      </div>
      <div>
        <label class="label" for={@form[:content].id}>
          <span class="label-text font-medium">{gettext("Content")}</span>
        </label>
        <.input
          field={@form[:content]}
          type="textarea"
          rows="8"
          placeholder={gettext("Paragraphs, separated by a blank line")}
        />
      </div>
      <div>
        <.input
          field={@form[:verse]}
          type="checkbox"
          label={gettext("In verse")}
        />
      </div>
      <div>
        <label class="label" for={@form[:trailer].id}>
          <span class="label-text font-medium">{gettext("Closing formula")}</span>
        </label>
        <.input field={@form[:trailer]} type="text" placeholder={gettext("e.g. FIN")} />
      </div>
      <div>
        <label class="label" for={@form[:note].id}>
          <span class="label-text font-medium">{gettext("Closing note")}</span>
        </label>
        <.input field={@form[:note]} type="textarea" rows="3" />
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
    """
  end
end
