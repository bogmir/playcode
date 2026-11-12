defmodule PlaycodeWeb.Admin.PlayDetailLive do
  @moduledoc """
  /admin/plays/:id: a play's overview: its structure and statistics, its downloads, the
  completeness switch that decides whether it is published, TEI validation, and the Word
  import that replaces its text.
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.StatisticsPanel

  alias Playcode.Catalogue
  alias Playcode.Export.TeiValidator
  alias Playcode.Export.TeiXml
  alias Playcode.Import.WordParser
  alias Playcode.PlayContent
  alias Playcode.PlayContent.InlineMarkup
  alias Playcode.Statistics
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play_with_all!(id)
    divisions = PlayContent.list_top_divisions(play.id)
    statistic = Statistics.get_statistics(play.id)

    {:ok,
     socket
     |> assign(:page_title, "Admin: #{play.title}")
     |> assign(:play, play)
     |> assign(:divisions, divisions)
     |> assign(:statistic, statistic)
     |> assign(:play_context, %{play: play, active_tab: :overview})
     |> assign(:validation_result, nil)
     |> assign(:validating, false)
     |> assign(:import_result, nil)
     |> allow_upload(:docx, accept: ~w(.docx), max_entries: 1, max_file_size: 10_000_000)}
  end

  @impl true
  def handle_event("validate_tei", _, socket) do
    play = socket.assigns.play
    xml = TeiXml.generate(play)
    result = TeiValidator.validate(xml)

    {:noreply, assign(socket, validation_result: result, validating: false)}
  end

  def handle_event("validate_upload", _, socket) do
    {:noreply, socket}
  end

  def handle_event("import_docx", _, socket) do
    play = socket.assigns.play

    consumed =
      consume_uploaded_entries(socket, :docx, fn %{path: path}, _entry ->
        # Copy to a temp file that persists after consume
        dest =
          Path.join(
            System.tmp_dir!(),
            "import-#{play.id}-#{System.unique_integer([:positive])}.docx"
          )

        File.cp!(path, dest)
        {:ok, dest}
      end)

    case consumed do
      [path] ->
        case WordParser.import_content(play.id, path) do
          {:ok, _play} ->
            File.rm(path)
            # Reload play data
            play = Catalogue.get_play_with_all!(play.id)
            divisions = PlayContent.list_top_divisions(play.id)
            statistic = Statistics.recompute(play.id)

            {:noreply,
             socket
             |> assign(play: play, divisions: divisions, statistic: statistic)
             |> assign(import_result: {:ok, gettext("Content imported successfully.")})
             |> put_flash(:info, gettext("Content imported successfully."))}

          {:error, reason} ->
            File.rm(path)
            {:noreply, assign(socket, import_result: {:error, inspect(reason)})}
        end

      _ ->
        {:noreply, assign(socket, import_result: {:error, gettext("No file uploaded.")})}
    end
  end

  def handle_event("set_status", %{"status" => status}, socket)
      when status in ~w(complete draft) do
    play = socket.assigns.play
    new_value = status == "complete"

    case Catalogue.update_play_from_form(play, %{"is_complete" => to_string(new_value)}) do
      {:ok, updated_play} ->
        msg =
          if new_value,
            do: gettext("Marked as complete."),
            else: gettext("Marked as draft.")

        {:noreply,
         socket
         |> assign(:play, updated_play)
         |> assign(:play_context, %{play: updated_play, active_tab: :overview})
         |> put_flash(:info, msg)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to update status."))}
    end
  end

  def handle_event("recompute_stats", _, socket) do
    statistic = Statistics.recompute(socket.assigns.play.id)

    {:noreply,
     assign(socket, statistic: statistic) |> put_flash(:info, gettext("Statistics recomputed."))}
  end

  defp error_to_string(:too_large), do: gettext("File is too large (max 10 MB).")
  defp error_to_string(:not_accepted), do: gettext("Only .docx files are accepted.")
  defp error_to_string(:too_many_files), do: gettext("Only one file allowed.")
  defp error_to_string(other), do: inspect(other)

  # One change of the file's revision history on a line: "2021 · Muñoz Pons, Carlos · Revisión…".
  defp revision(change) do
    [change.date, change.people, change.description, change.note]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
    |> InlineMarkup.plain()
  end

  # An act's whole verses, from the statistics' distribution, keyed as it keys them.
  defp act_verses(nil, _division), do: nil

  defp act_verses(statistic, division) do
    Enum.find_value(statistic.data["verse_distribution"] || [], fn
      %{"act" => act, "count" => count} ->
        if act == (division.number || division.position), do: count
    end)
  end

  defp acts(divisions), do: Enum.reject(divisions, &(&1.type == "elenco"))

  # The top divisions by the play's own name for them: "jornadas", "actos".
  defp acts_label(%{data: %{"act_label" => label}}) when is_binary(label),
    do: label |> PlayLabels.act_label_plural() |> String.downcase()

  defp acts_label(_statistic), do: gettext("acts")

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_header>
        {@play.title}
        <:subtitle>
          {@play.author_name} ·
          <code class="rounded border border-base-300 bg-base-100 px-1.5 font-mono text-xs">
            {@play.code}
          </code>
          · {Playcode.Catalogue.Play.language_name(@play.language)} · {PlayLabels.form_label(
            Playcode.Catalogue.Play.form(@play)
          )}
        </:subtitle>
        <:actions>
          <.download_group base={"/admin/plays/#{@play.id}/export"} target="_blank" />
          <button
            phx-click="validate_tei"
            class="btn btn-sm btn-outline btn-primary"
            disabled={@validating}
          >
            {gettext("Validate TEI-XML")}
          </button>
          <.link navigate={~p"/admin/plays/#{@play.id}/edit"} class="btn btn-sm btn-primary">
            {gettext("Edit metadata")}
          </.link>
        </:actions>
      </.page_header>

      <div :if={@validation_result}>
        <div :if={@validation_result == {:ok, :valid}} role="alert" class="alert alert-success">
          <.icon name="hero-check-circle-mini" class="size-5" />
          <span>{gettext("TEI-XML is valid against TEI P5 schema.")}</span>
        </div>
        <div
          :if={@validation_result == {:error, :xmllint_not_found}}
          role="alert"
          class="alert alert-warning"
        >
          <.icon name="hero-exclamation-triangle-mini" class="size-5" />
          <span>{gettext("xmllint is not installed. Cannot validate.")}</span>
        </div>
        <div
          :if={@validation_result == {:error, :schema_not_found}}
          role="alert"
          class="alert alert-warning"
        >
          <.icon name="hero-exclamation-triangle-mini" class="size-5" />
          <span>{gettext("TEI schema file not found.")}</span>
        </div>
        <%= if match?({:error, errors} when is_list(errors), @validation_result) do %>
          <% {:error, errors} = @validation_result %>
          <div role="alert" class="alert alert-error">
            <.icon name="hero-x-circle-mini" class="size-5" />
            <div>
              <span class="font-medium">{gettext("TEI-XML validation failed:")}</span>
              <details class="mt-2">
                <summary class="cursor-pointer text-sm underline">
                  {gettext("Show %{count} error(s)", count: length(errors))}
                </summary>
                <ul class="mt-2 ml-4 list-disc text-xs font-mono space-y-1">
                  <li :for={error <- errors}>{error}</li>
                </ul>
              </details>
            </div>
          </div>
        <% end %>
      </div>

      <.state_band play={@play} deployed={@play_deployed} />

      <div
        :if={@play_counts}
        id="play-counts"
        class="mb-8 grid grid-cols-[repeat(auto-fit,minmax(9rem,1fr))] gap-3"
      >
        <.count_tile
          :if={@play.verse_count}
          count={@play.verse_count}
          label={gettext("verses")}
          navigate={~p"/admin/plays/#{@play.id}/content"}
        />
        <.count_tile
          count={length(acts(@divisions))}
          label={acts_label(@statistic)}
          navigate={~p"/admin/plays/#{@play.id}/content"}
        />
        <.count_tile
          count={@play_counts.characters}
          label={gettext("characters")}
          navigate={~p"/admin/plays/#{@play.id}/content"}
        />
        <.count_tile
          count={@play_counts.performances}
          label={gettext("performances")}
          navigate={~p"/admin/plays/#{@play.id}/performances"}
        />
        <.count_tile
          count={@play_counts.bibliography}
          label={gettext("bibliography entries")}
          navigate={~p"/admin/plays/#{@play.id}/bibliography"}
        />
        <.count_tile
          count={@play_counts.notes}
          label={gettext("notes")}
          navigate={~p"/admin/plays/#{@play.id}/notes"}
        />
        <.count_tile
          count={@play_counts.witnesses}
          label={gettext("witnesses")}
          navigate={~p"/admin/plays/#{@play.id}/witnesses"}
        />
      </div>

      <div class="grid gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]">
        <div>
          <.card title={gettext("Record")}>
            <:action>
              <.link navigate={~p"/admin/plays/#{@play.id}/edit"} class="link link-primary">
                {gettext("Edit")}
              </.link>
            </:action>
            <.field_list>
              <:item :if={@play.original_title} label={gettext("Original title")}>
                {@play.original_title}
              </:item>
              <:item label={gettext("Language")}>
                {Playcode.Catalogue.Play.language_name(@play.language)}
              </:item>
              <:item :if={@play.author_attribution} label={gettext("Attribution")}>
                {@play.author_attribution}
              </:item>
              <:item :if={Playcode.Catalogue.Play.composition_years(@play)} label={gettext("Dating")}>
                {Playcode.Catalogue.Play.composition_years(@play)}
              </:item>
              <:item :if={@play.historical_time} label={gettext("Historical time")}>
                {PlayLabels.historical_time_label(@play.historical_time)}
              </:item>
              <:item :if={@play.pub_place || @play.publication_date} label={gettext("Publication")}>
                {[@play.pub_place, @play.publication_date]
                |> Enum.reject(&is_nil/1)
                |> Enum.join(", ")}
              </:item>
              <:item :if={@play.publisher} label={gettext("Publisher")}>{@play.publisher}</:item>
              <:item :if={@play.edition_title} label={gettext("Edition title")}>
                {@play.edition_title}
              </:item>
              <:item :if={@play.emothe_id} label={gettext("EMOTHE ID")}>{@play.emothe_id}</:item>
            </.field_list>
            <details
              :if={
                @play.authority || @play.sponsor || @play.funder || @play.availability_note ||
                  @play.licence_url || @play.licence_text
              }
              class="mt-3 border-t border-base-300 pt-2.5"
            >
              <summary class="cursor-pointer text-sm font-semibold text-primary">
                {gettext("Project, funding and availability")}
              </summary>
              <.field_list class="mt-2.5">
                <:item :if={@play.authority} label={gettext("Authority")}>{@play.authority}</:item>
                <:item :if={@play.sponsor} label={gettext("Sponsor")}>{@play.sponsor}</:item>
                <:item :if={@play.funder} label={gettext("Funder")}>{@play.funder}</:item>
                <:item :if={@play.availability_note} label={gettext("Availability")}>
                  {@play.availability_note}
                </:item>
                <:item :if={@play.licence_url || @play.licence_text} label={gettext("Licence")}>
                  <a
                    :if={@play.licence_url}
                    href={@play.licence_url}
                    target="_blank"
                    class="link link-primary"
                  >
                    {@play.licence_text || @play.licence_url}
                  </a>
                  <span :if={!@play.licence_url}>{@play.licence_text}</span>
                </:item>
              </.field_list>
            </details>
          </.card>

          <.card :if={@divisions != []} title={gettext("Structure")}>
            <:action>
              <.link navigate={~p"/admin/plays/#{@play.id}/content"} class="link link-primary">
                {gettext("Open Content")}
              </.link>
            </:action>
            <ol class="list-decimal pl-5">
              <li :for={division <- @divisions} class="py-0.5">
                {division.title || division.type}
                <span
                  :if={division.type == "elenco" && @play_counts}
                  class="text-sm text-base-content/70"
                >
                  · {ngettext("%{count} character", "%{count} characters", @play_counts.characters)}
                </span>
                <span :if={act_verses(@statistic, division)} class="text-sm text-base-content/70">
                  · {ngettext("%{count} verse", "%{count} verses", act_verses(@statistic, division))}
                </span>
              </li>
            </ol>
          </.card>
        </div>

        <div>
          <.card :if={@play.editors != []} title={gettext("Edition")}>
            <:action>
              <.link navigate={~p"/admin/plays/#{@play.id}/editors"} class="link link-primary">
                {gettext("Edit")}
              </.link>
            </:action>
            <ul class="divide-y divide-base-300">
              <li :for={editor <- @play.editors} class="flex justify-between gap-4 py-1.5">
                <span>{editor.person_name}</span>
                <span class="text-right text-sm text-base-content/70">
                  {PlayLabels.editor_role_label(editor.role)}{if editor.organization,
                    do: " · #{editor.organization}"}
                </span>
              </li>
            </ul>
          </.card>

          <.card
            :if={@play.relationship_type || @play.derived_plays != []}
            title={gettext("Work Relationship")}
          >
            <p :if={@play.relationship_type}>
              <span class="badge badge-outline badge-sm mr-2">
                {PlayLabels.relationship_type_label(@play.relationship_type)}
              </span>
              <%= if @play.parent_play do %>
                {gettext("of")}
                <.link navigate={~p"/admin/plays/#{@play.parent_play.id}"} class="link link-primary">
                  {@play.parent_play.title}
                </.link>
                <span class="text-base-content/70">({@play.parent_play.code})</span>
              <% else %>
                <span :if={@play.original_title} class="text-base-content/70">
                  {gettext("of")} {@play.original_title} ({gettext("not linked")})
                </span>
              <% end %>
            </p>
            <div :if={@play.derived_plays != []} class="mt-2">
              <span class="text-sm text-base-content/70">{gettext("Derived works:")}</span>
              <ul class="mt-1 ml-4 list-disc">
                <li :for={derived <- @play.derived_plays}>
                  <.link navigate={~p"/admin/plays/#{derived.id}"} class="link link-primary">
                    {derived.title}
                  </.link>
                  <span class="text-base-content/70">({derived.code})</span>
                  <span :if={derived.relationship_type} class="badge badge-ghost badge-sm ml-1">
                    {PlayLabels.relationship_type_label(derived.relationship_type)}
                  </span>
                </li>
              </ul>
            </div>
          </.card>

          <.card :if={@play.revisions != []} title={gettext("Revisions")}>
            <ul id="revisions" class="divide-y divide-base-300">
              <li :for={change <- @play.revisions} class="py-1.5 text-sm">{revision(change)}</li>
            </ul>
          </.card>

          <.card title={gettext("Statistics")}>
            <:action>
              <a :if={@statistic} href="#statistics" class="link link-primary">
                {gettext("See all")}
              </a>
            </:action>
            <.field_list :if={@statistic}>
              <:item label={gettext("Speeches")}>{@statistic.data["speeches"]}</:item>
              <:item label={gettext("Stage directions")}>
                {@statistic.data["total_stage_directions"]}
              </:item>
              <:item label={gettext("Computed")}>
                {Calendar.strftime(@statistic.computed_at, "%Y-%m-%d %H:%M")}
              </:item>
            </.field_list>
            <button phx-click="recompute_stats" class="btn btn-sm btn-ghost mt-2 -ml-2">
              <.icon name="hero-arrow-path-mini" class="size-4" /> {gettext("Recompute")}
            </button>
          </.card>

          <.card :if={!@play.is_complete} title={gettext("Replace the text from Word")} dashed>
            <p class="mb-3 text-sm text-base-content/80">
              {gettext("Upload a premarcado .docx file.")}
              <strong>{gettext("It replaces all the current text.")}</strong>
              {gettext("Drafts only.")}
            </p>
            <form id="docx-upload-form" phx-submit="import_docx" phx-change="validate_upload">
              <.drop_zone
                upload={@uploads.docx}
                label={gettext("Drop the Word file here, or choose it")}
              />
              <div :for={entry <- @uploads.docx.entries} class="mt-1">
                <span class="font-mono text-sm">{entry.client_name}</span>
                <div :for={err <- upload_errors(@uploads.docx, entry)} class="text-error text-xs">
                  {error_to_string(err)}
                </div>
              </div>
              <button
                type="submit"
                class="btn btn-outline btn-primary btn-sm mt-2"
                disabled={@uploads.docx.entries == []}
              >
                {gettext("Replace the text")}
              </button>
            </form>
            <div :if={match?({:error, _}, @import_result)} class="mt-3 alert alert-error text-sm">
              <.icon name="hero-x-circle-mini" class="size-4" />
              {elem(@import_result, 1)}
            </div>
          </.card>
        </div>
      </div>

      <section :if={@statistic} id="statistics" class="mt-4">
        <h2 class="mb-3 text-lg font-semibold text-base-content">{gettext("Statistics")}</h2>
        <.stats_panel statistic={@statistic} play={@play} />
      </section>
    </.page>
    """
  end
end
