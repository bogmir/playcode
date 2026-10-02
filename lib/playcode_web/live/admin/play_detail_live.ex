defmodule PlaycodeWeb.Admin.PlayDetailLive do
  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.StatisticsPanel

  alias Playcode.Catalogue
  alias Playcode.Export.TeiValidator
  alias Playcode.Export.TeiXml
  alias Playcode.Import.WordParser
  alias Playcode.PlayContent
  alias Playcode.Statistics
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play_with_all!(id)
    characters = PlayContent.list_characters(play.id)
    divisions = PlayContent.list_top_divisions(play.id)
    statistic = Statistics.get_statistics(play.id)

    {:ok,
     socket
     |> assign(:page_title, "Admin: #{play.title}")
     |> assign(:play, play)
     |> assign(:characters, characters)
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
            characters = PlayContent.list_characters(play.id)
            divisions = PlayContent.list_top_divisions(play.id)
            statistic = Statistics.recompute(play.id)

            {:noreply,
             socket
             |> assign(
               play: play,
               characters: characters,
               divisions: divisions,
               statistic: statistic
             )
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

  defp relationship_type_label("traduccion"), do: gettext("Translation")
  defp relationship_type_label("adaptacion"), do: gettext("Adaptation")
  defp relationship_type_label("refundicion"), do: gettext("Reworking")
  defp relationship_type_label(_), do: ""

  defp error_to_string(:too_large), do: gettext("File is too large (max 10 MB).")
  defp error_to_string(:not_accepted), do: gettext("Only .docx files are accepted.")
  defp error_to_string(:too_many_files), do: gettext("Only one file allowed.")
  defp error_to_string(other), do: inspect(other)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">{@play.title}</h1>
          <p class="mt-1 text-sm text-base-content/60">
            {@play.author_name} — {@play.code}
          </p>
        </div>
        <div class="flex items-center gap-1">
          <span class="text-xs text-base-content/40 mr-1">{gettext("Export")}</span>
          <a
            href={~p"/admin/plays/#{@play.id}/export/tei"}
            target="_blank"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Export TEI-XML")}
          >
            <.icon name="hero-code-bracket-mini" class="size-4" />
          </a>
          <a
            href={~p"/admin/plays/#{@play.id}/export/html"}
            target="_blank"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Export HTML")}
          >
            <.icon name="hero-globe-alt-mini" class="size-4" />
          </a>
          <a
            href={~p"/admin/plays/#{@play.id}/export/pdf"}
            target="_blank"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Export PDF")}
          >
            <.icon name="hero-document-arrow-down-mini" class="size-4" />
          </a>
          <a
            href={~p"/admin/plays/#{@play.id}/export/epub"}
            target="_blank"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Export EPUB")}
          >
            <.icon name="hero-book-open-mini" class="size-4" />
          </a>
          <span class="border-l border-base-300 h-4 mx-1"></span>
          <button
            phx-click="validate_tei"
            class="btn btn-ghost btn-xs tooltip"
            data-tip={gettext("Validate TEI-XML")}
            disabled={@validating}
          >
            <.icon name="hero-check-badge-mini" class="size-4" />
          </button>
        </div>
      </div>

      <%!-- Validation Result --%>
      <div :if={@validation_result} class="mb-6">
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

      <%!-- Status Toggle --%>
      <section class="mb-8">
        <div class="flex items-center gap-3">
          <span class="text-sm font-medium text-base-content/70">{gettext("Status")}</span>
          <div class="join" role="group" aria-label={gettext("Status")}>
            <button
              phx-click="set_status"
              phx-value-status="draft"
              aria-pressed={to_string(!@play.is_complete)}
              class={"btn btn-sm join-item gap-1.5 #{if !@play.is_complete, do: "btn-warning", else: "btn-ghost border-base-300"}"}
            >
              <.icon name="hero-pencil-mini" class="size-4" />
              {gettext("Draft")}
            </button>
            <button
              phx-click="set_status"
              phx-value-status="complete"
              aria-pressed={to_string(@play.is_complete)}
              class={"btn btn-sm join-item gap-1.5 #{if @play.is_complete, do: "btn-success", else: "btn-ghost border-base-300"}"}
            >
              <.icon name="hero-check-circle-mini" class="size-4" />
              {gettext("Complete")}
            </button>
          </div>
        </div>
      </section>

      <%!-- Import Content --%>
      <section :if={!@play.is_complete} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">
          {gettext("Import content")}
        </h2>
        <div class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm">
          <p class="text-sm text-base-content/60 mb-3">
            {gettext(
              "Upload a premarcado .docx file to import play content (divisions, speeches, verses, stage directions). Existing content will be replaced."
            )}
          </p>
          <form
            id="docx-upload-form"
            phx-submit="import_docx"
            phx-change="validate_upload"
            class="flex items-end gap-3"
          >
            <div class="flex-1">
              <.live_file_input
                upload={@uploads.docx}
                class="file-input file-input-bordered file-input-sm w-full"
              />
              <div :for={entry <- @uploads.docx.entries} class="mt-1">
                <div :for={err <- upload_errors(@uploads.docx, entry)} class="text-error text-xs">
                  {error_to_string(err)}
                </div>
              </div>
            </div>
            <button
              type="submit"
              class="btn btn-primary btn-sm"
              disabled={@uploads.docx.entries == []}
            >
              <.icon name="hero-arrow-up-tray-mini" class="size-4" />
              {gettext("Import")}
            </button>
          </form>
          <div :if={match?({:error, _}, @import_result)} class="mt-3 alert alert-error text-sm">
            <.icon name="hero-x-circle-mini" class="size-4" />
            {elem(@import_result, 1)}
          </div>
        </div>
      </section>

      <%!-- Metadata --%>
      <section class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">{gettext("Metadata")}</h2>
        <div class="grid grid-cols-1 gap-4 rounded-box border border-base-300 bg-base-100 p-4 text-sm shadow-sm md:grid-cols-2">
          <div :if={@play.original_title}>
            <span class="font-medium">{gettext("Original title:")}</span>
            <span class="text-base-content/70">{@play.original_title}</span>
          </div>
          <div :if={@play.emothe_id}>
            <span class="font-medium">{gettext("EMOTHE ID:")}</span>
            <span class="text-base-content/70">{@play.emothe_id}</span>
          </div>
          <div class="md:col-span-2">
            <span class="font-medium">{gettext("Play URL:")}</span>
            <a
              href={~p"/plays/#{@play.code}"}
              target="_blank"
              class="link link-primary text-xs break-all"
            >
              {PlaycodeWeb.Endpoint.url() <> ~p"/plays/#{@play.code}"}
            </a>
          </div>
          <div>
            <span class="font-medium">{gettext("Language:")}</span>
            <span class="text-base-content/70">
              {Playcode.Catalogue.Play.language_name(@play.language)}
            </span>
          </div>
          <div>
            <span class="font-medium">{gettext("Verse count:")}</span>
            <span class="text-base-content/70">{@play.verse_count || gettext("N/A")}</span>
          </div>
          <div>
            <span class="font-medium">{gettext("Attribution:")}</span>
            <span class="text-base-content/70">{@play.author_attribution || gettext("N/A")}</span>
          </div>
          <div>
            <span class="font-medium">{gettext("Publication:")}</span>
            <span class="text-base-content/70">{@play.pub_place} ({@play.publication_date})</span>
          </div>
          <div :if={@play.publisher}>
            <span class="font-medium">{gettext("Publisher:")}</span>
            <span class="text-base-content/70">{@play.publisher}</span>
          </div>
          <div :if={@play.authority}>
            <span class="font-medium">{gettext("Authority:")}</span>
            <span class="text-base-content/70">{@play.authority}</span>
          </div>
          <div :if={@play.availability_note} class="md:col-span-2">
            <span class="font-medium">{gettext("Availability:")}</span>
            <span class="text-base-content/70 text-xs">{@play.availability_note}</span>
          </div>
          <div :if={@play.sponsor} class="md:col-span-2">
            <span class="font-medium">{gettext("Sponsor:")}</span>
            <span class="text-base-content/70">{@play.sponsor}</span>
          </div>
          <div :if={@play.funder} class="md:col-span-2">
            <span class="font-medium">{gettext("Funder:")}</span>
            <span class="text-base-content/70">{@play.funder}</span>
          </div>
          <div :if={@play.edition_title} class="md:col-span-2">
            <span class="font-medium">{gettext("Edition title:")}</span>
            <span class="text-base-content/70">{@play.edition_title}</span>
          </div>
          <div :if={@play.licence_url || @play.licence_text} class="md:col-span-2">
            <span class="font-medium">{gettext("Licence:")}</span>
            <span class="text-base-content/70">
              <%= if @play.licence_url do %>
                <a href={@play.licence_url} target="_blank" class="link link-primary">
                  {@play.licence_text || @play.licence_url}
                </a>
              <% else %>
                {@play.licence_text}
              <% end %>
            </span>
          </div>
        </div>
      </section>

      <%!-- Work Relationship --%>
      <section
        :if={@play.relationship_type || @play.derived_plays != []}
        class="mb-8"
      >
        <h2 class="mb-3 text-lg font-semibold text-base-content">
          {gettext("Work Relationship")}
        </h2>
        <div class="rounded-box border border-base-300 bg-base-100 p-4 text-sm shadow-sm space-y-3">
          <div :if={@play.relationship_type}>
            <span class="badge badge-outline badge-sm mr-2">
              {relationship_type_label(@play.relationship_type)}
            </span>
            <%= if @play.parent_play do %>
              <span>
                {gettext("of")}
                <.link
                  navigate={~p"/admin/plays/#{@play.parent_play.id}"}
                  class="link link-primary"
                >
                  {@play.parent_play.title}
                </.link>
                <span class="text-base-content/50">({@play.parent_play.code})</span>
              </span>
            <% else %>
              <span :if={@play.original_title} class="text-base-content/70">
                {gettext("of")} {@play.original_title}
                <span class="text-base-content/40">({gettext("not linked")})</span>
              </span>
            <% end %>
          </div>
          <div :if={@play.derived_plays != []}>
            <span class="font-medium">{gettext("Derived works:")}</span>
            <ul class="mt-1 ml-4 list-disc">
              <li :for={derived <- @play.derived_plays}>
                <.link
                  navigate={~p"/admin/plays/#{derived.id}"}
                  class="link link-primary"
                >
                  {derived.title}
                </.link>
                <span class="text-base-content/50">({derived.code})</span>
                <span :if={derived.relationship_type} class="badge badge-ghost badge-xs ml-1">
                  {relationship_type_label(derived.relationship_type)}
                </span>
              </li>
            </ul>
          </div>
        </div>
      </section>

      <%!-- Editors --%>
      <section :if={@play.editors != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">{gettext("Editors")}</h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={editor <- @play.editors} class="flex items-center justify-between p-3">
            <span class="font-medium">{editor.person_name}</span>
            <span class="text-sm text-base-content/60">
              {PlayLabels.editor_role_label(editor.role)} {if editor.organization,
                do: "— #{editor.organization}"}
            </span>
          </div>
        </div>
      </section>

      <%!-- Characters --%>
      <section :if={@characters != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">
          {gettext("Characters")} ({length(@characters)})
        </h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={char <- @characters} class="flex items-center gap-3 p-3">
            <span class="font-medium">{char.name}</span>
            <span :if={char.description} class="text-sm text-base-content/60">
              {char.description}
            </span>
            <span :if={char.is_hidden} class="badge badge-ghost badge-sm">
              {gettext("hidden")}
            </span>
          </div>
        </div>
      </section>

      <%!-- Structure --%>
      <section :if={@divisions != []} class="mb-8">
        <h2 class="mb-3 text-lg font-semibold text-base-content">{gettext("Structure")}</h2>
        <div class="divide-y rounded-box border border-base-300 bg-base-100 shadow-sm">
          <div :for={div <- @divisions} class="p-3">
            <span class="font-medium">{div.title || div.type}</span>
            <span class="ml-2 text-sm text-base-content/60">{div.type} {div.number}</span>
            <div :if={div.children != []} class="ml-6 mt-1">
              <div :for={child <- div.children} class="text-sm text-base-content/70">
                {child.title || child.type} {child.number}
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- Statistics --%>
      <section class="mb-8">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{gettext("Statistics")}</h2>
          <button phx-click="recompute_stats" class="btn btn-xs btn-ghost">
            <.icon name="hero-arrow-path-mini" class="size-4" /> {gettext("Recompute")}
          </button>
        </div>
        <div :if={@statistic} class="mb-4 text-xs text-base-content/60">
          {gettext("Last computed:")} {Calendar.strftime(@statistic.computed_at, "%Y-%m-%d %H:%M")}
        </div>
        <.stats_panel :if={@statistic} statistic={@statistic} play={@play} />
      </section>
    </div>
    """
  end
end
