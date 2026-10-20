defmodule PlaycodeWeb.Admin.EntryFields do
  @moduledoc """
  The inputs of a bibliography entry, shared by the tabs that edit one: a play's
  Bibliography tab and, for a performance's source, the Performances tab. Only the markup is
  shared. The page owns the `<form>`, its events and the entry's changeset.
  """

  use PlaycodeWeb, :html

  alias Playcode.Bibliography.Entry
  alias Playcode.Catalogue.Play
  alias PlaycodeWeb.PlayLabels

  attr :form, Phoenix.HTML.Form, required: true, doc: "an entry's form, `as: \"entry\"`"
  attr :kinds, :list, default: Entry.kinds(), doc: "the kinds the select offers"

  def entry_fields(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="grid gap-4 sm:grid-cols-3">
        <.input
          field={@form[:kind]}
          type="select"
          label={gettext("Kind")}
          options={PlayLabels.bibliography_kind_options(@kinds)}
        />
        <.input
          field={@form[:pub_type]}
          type="select"
          label={gettext("Type")}
          prompt={gettext("Not stated")}
          options={PlayLabels.pub_type_options()}
        />
        <.input
          field={@form[:language]}
          type="select"
          label={gettext("Language")}
          prompt={gettext("Not stated")}
          options={language_options()}
        />
      </div>

      <fieldset class="fieldset rounded-box border border-base-300 p-4">
        <legend class="fieldset-legend">{gettext("Article or chapter")}</legend>
        <div class="grid gap-3 sm:grid-cols-2">
          <.input field={@form[:analytic_author]} label={gettext("Author")} />
          <.input field={@form[:analytic_title]} label={gettext("Title")} />
          <.input field={@form[:analytic_editors]} label={gettext("Editors")} />
          <.input field={@form[:analytic_translators]} label={gettext("Translators")} />
        </div>
      </fieldset>

      <fieldset class="fieldset rounded-box border border-base-300 p-4">
        <legend class="fieldset-legend">{gettext("Book or journal")}</legend>
        <div class="grid gap-3 sm:grid-cols-2">
          <.input field={@form[:monogr_author]} label={gettext("Author")} />
          <.input field={@form[:monogr_title]} label={gettext("Title")} />
          <.input field={@form[:monogr_editors]} label={gettext("Editors")} />
          <.input field={@form[:monogr_translators]} label={gettext("Translators")} />
        </div>
      </fieldset>

      <fieldset class="fieldset rounded-box border border-base-300 p-4">
        <legend class="fieldset-legend">{gettext("Publication")}</legend>
        <div class="grid gap-3 sm:grid-cols-3">
          <.input field={@form[:pub_place]} label={gettext("Place")} />
          <.input field={@form[:publisher]} label={gettext("Publisher")} />
          <.input field={@form[:year_text]} label={gettext("Year")} />
          <.input field={@form[:edition]} label={gettext("Edition")} />
          <.input field={@form[:volume]} label={gettext("Volume")} />
          <.input field={@form[:volumes_total]} label={gettext("Number of volumes")} />
          <.input field={@form[:issue]} label={gettext("Issue")} />
          <.input field={@form[:pages]} label={gettext("Pages")} />
          <.input field={@form[:series]} label={gettext("Series")} />
          <.input field={@form[:original_title]} label={gettext("Original title")} />
          <.input field={@form[:url]} label={gettext("URL")} />
          <.input field={@form[:url_accessed_on]} label={gettext("Accessed on")} />
        </div>
        <div
          :if={Phoenix.HTML.Form.input_value(@form, :kind) == "modern_edition"}
          class="mt-3 grid gap-3 sm:grid-cols-3"
        >
          <.input field={@form[:siglum]} label={gettext("Siglum")} />
        </div>
      </fieldset>

      <fieldset class="fieldset rounded-box border border-base-300 p-4">
        <legend class="fieldset-legend">{gettext("Notes")}</legend>
        <div class="grid gap-3 sm:grid-cols-2">
          <.input
            field={@form[:public_note]}
            type="textarea"
            rows="2"
            label={gettext("Printed note")}
          />
          <.input
            field={@form[:note]}
            type="textarea"
            rows="2"
            label={gettext("Internal note, for researchers only")}
          />
        </div>
      </fieldset>
    </div>
    """
  end

  defp language_options, do: Enum.map(Entry.languages(), &{Play.language_name(&1), &1})
end
