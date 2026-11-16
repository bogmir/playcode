defmodule PlaycodeWeb.Admin.ImportLive do
  @moduledoc """
  /admin/plays/import: upload TEI files. A file whose code already exists is previewed
  first (`TeiImport.preview_import/1`): what the re-import replaces and what it keeps.

  The page is in one `@phase`: `:idle` (choose files; the last import's report, if any),
  `:confirming` (the uploaded files wait in `@pending` behind `@previews`) or `:importing`
  (one file per message). Import leads from `:idle` to either of the others, Confirm and
  Cancel out of `:confirming`, the last file back to `:idle`.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Import.TeiImport
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Import TEI-XML"))
     |> assign(:successes, [])
     |> assign(:errors, [])
     |> assign(:phase, :idle)
     |> assign(:import_total, 0)
     |> assign(:import_done, 0)
     |> assign(:pending, [])
     |> assign(:previews, [])
     |> assign(:overwrite_edits, false)
     |> allow_upload(:tei_files,
       accept: ~w(.xml),
       max_entries: 20,
       max_file_size: 20_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :tei_files, ref)}
  end

  def handle_event("import", _params, %{assigns: %{phase: :idle}} = socket) do
    # Consume uploads: copy each to a stable temp path so we can process async
    pending_files =
      consume_uploaded_entries(socket, :tei_files, fn %{path: path}, entry ->
        dest =
          Path.join(
            System.tmp_dir!(),
            "playcode-import-#{System.unique_integer([:positive])}.xml"
          )

        File.cp!(path, dest)
        {:ok, {dest, entry.client_name}}
      end)

    {:noreply, start_or_confirm(socket, pending_files)}
  end

  # The button is disabled until the box is ticked, but the event can still be pushed.
  def handle_event("confirm_import", _params, %{assigns: %{phase: :confirming}} = socket) do
    if edits_unconfirmed?(socket.assigns.previews, socket.assigns.overwrite_edits),
      do: {:noreply, socket},
      else: {:noreply, start_import(socket, socket.assigns.pending)}
  end

  def handle_event("overwrite_edits", params, socket) do
    {:noreply, assign(socket, :overwrite_edits, params["overwrite_edits"] == "true")}
  end

  def handle_event("cancel_import", _params, %{assigns: %{phase: :confirming}} = socket) do
    Enum.each(socket.assigns.pending, fn {path, _filename} -> File.rm(path) end)

    {:noreply, socket |> assign(:phase, :idle) |> assign(:pending, []) |> assign(:previews, [])}
  end

  # A click the page's phase has moved past: the second of two on one button, mostly.
  def handle_event(event, _params, socket)
      when event in ~w(import confirm_import cancel_import),
      do: {:noreply, socket}

  # An import that lands on a play we already hold replaces its whole text, and one whose
  # file brings references may add one Playcode holds under a corrected description; a
  # split verse's parts out of order are worth correcting in the file first. Say so and
  # wait for a click; a batch of new plays with none of these goes straight through.
  defp start_or_confirm(socket, pending) do
    previews =
      for {path, filename} <- pending,
          {:ok, preview} <- [TeiImport.preview_import(path)],
          preview.existing || preview.bibliography_adds != [] || preview.bibliography_skips != [] ||
            preview.split_verses != [],
          do: Map.put(preview, :filename, filename)

    if previews == [] do
      start_import(socket, pending)
    else
      socket
      |> assign(:phase, :confirming)
      |> assign(:pending, pending)
      |> assign(:previews, previews)
      |> assign(:overwrite_edits, false)
      |> assign(:successes, [])
      |> assign(:errors, [])
    end
  end

  defp start_import(socket, pending) do
    send(self(), {:import_next, pending})

    socket
    |> assign(:phase, :importing)
    |> assign(:pending, [])
    |> assign(:previews, [])
    |> assign(:successes, [])
    |> assign(:errors, [])
    |> assign(:import_total, length(pending))
    |> assign(:import_done, 0)
  end

  @impl true
  def handle_info({:import_next, []}, socket) do
    successes = Enum.reverse(socket.assigns.successes)
    errors = Enum.reverse(socket.assigns.errors)

    socket = assign(socket, :phase, :idle)
    socket = assign(socket, :successes, successes)

    socket =
      case errors do
        [] ->
          socket

        _ ->
          error_msg =
            Enum.map_join(errors, "\n", fn {file, reason} ->
              "#{file}: #{format_error(reason)}"
            end)

          put_flash(socket, :error, "#{gettext("Import errors")}:\n#{error_msg}")
      end

    socket =
      case successes do
        [] ->
          socket

        _ ->
          put_flash(
            socket,
            :info,
            gettext("Successfully imported %{count} play(s).", count: length(successes))
          )
      end

    {:noreply, socket}
  end

  def handle_info({:import_next, [{path, filename} | rest]}, socket) do
    socket =
      case TeiImport.import_file(path) do
        {:ok, play} ->
          LiveHelpers.log_activity(socket, "import", "play", play.id, %{
            filename: filename,
            title: play.title,
            code: play.code
          })

          # validation_warnings = validate_source_file(path)
          validation_warnings = []
          success = {filename, play.title, play.code, play.id, validation_warnings}
          update(socket, :successes, &[success | &1])

        {:error, reason} ->
          update(socket, :errors, &[{filename, reason} | &1])
      end

    # Every pending path is the temp copy the "import" handler made.
    File.rm(path)

    send(self(), {:import_next, rest})
    {:noreply, update(socket, :import_done, &(&1 + 1))}
  end

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error({:xml_parse_error, detail}), do: "XML parse error: #{inspect(detail)}"

  defp format_error({:play_already_exists, code}),
    do: gettext("Play with code %{code} already exists", code: code)

  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_header>
        {gettext("Import TEI-XML Files")}
        <:subtitle>
          {gettext("Import one or many TEI files and review successful ingestions.")}
        </:subtitle>
      </.page_header>

      <%!-- Upload files from browser --%>
      <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Select Files")}</h2>
          <p class="mb-3 text-sm text-base-content/70">
            {gettext("Choose one or more TEI-XML files from your computer.")}
          </p>
          <form id="upload-form" phx-submit="import" phx-change="validate">
            <div class="mb-4">
              <.drop_zone
                upload={@uploads.tei_files}
                label={gettext("Drop TEI-XML files here, or choose them")}
                disabled={@phase != :idle}
              />
            </div>

            <div
              :for={entry <- @uploads.tei_files.entries}
              class="mb-2 flex items-center gap-3 rounded-box bg-base-200 px-2 py-1.5"
            >
              <span class="text-sm font-mono flex-1">{entry.client_name}</span>
              <progress value={entry.progress} max="100" class="progress progress-primary w-32" />
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="btn btn-ghost btn-xs text-error tooltip"
                aria-label={gettext("Remove")}
                data-tip={gettext("Remove")}
              >
                <.icon name="hero-x-mark-mini" class="size-4" />
              </button>
            </div>

            <div :for={err <- upload_errors(@uploads.tei_files)} class="text-error text-sm mb-2">
              {upload_error_to_string(err)}
            </div>

            <button
              type="submit"
              class="btn btn-primary mt-2"
              disabled={@uploads.tei_files.entries == [] || @phase != :idle}
            >
              {import_label(length(@uploads.tei_files.entries))}
            </button>
          </form>
        </div>
      </div>

      <%!-- Replacement confirmation --%>
      <div
        :if={@phase == :confirming}
        id="import-confirmation"
        class="card mb-6 border border-warning bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title text-warning">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            {if existing_count(@previews) > 0,
              do: gettext("%{count} of these plays already exist", count: existing_count(@previews)),
              else: gettext("Check the references before importing")}
          </h2>
          <p :if={existing_count(@previews) > 0} class="text-sm text-base-content/70">
            {gettext(
              "Importing replaces the text and the records that came from TEI. Anything entered by hand is kept."
            )}
          </p>

          <ul class="mt-3 space-y-3">
            <li :for={p <- @previews} class="rounded-box bg-base-200 px-3 py-2">
              <div class="flex items-center gap-2">
                <span class="badge badge-primary badge-sm">{p.code}</span>
                <span class="font-medium">{if p.existing, do: p.existing.title, else: p.title}</span>
                <span :if={!p.existing} class="badge badge-ghost badge-sm">
                  {gettext("new play")}
                </span>
                <span :if={p.archived} class="badge badge-ghost badge-sm">
                  {gettext("archived — will be restored")}
                </span>
              </div>
              <div :if={p.existing} class="mt-1 text-xs text-base-content/70">
                {gettext(
                  "Replaces %{divisions} division(s), %{elements} element(s), %{characters} character(s) and %{tei} record(s) imported from TEI.",
                  divisions: p.replaces.divisions,
                  elements: p.replaces.elements,
                  characters: p.replaces.characters,
                  tei: tei_total(p)
                )}
                <span :if={p.edited > 0} class="font-medium text-warning">
                  {gettext(
                    "%{count} row(s) from the file were edited by hand since its import: importing replaces them too.",
                    count: p.edited
                  )}
                </span>
              </div>
              <div :if={preserved_total(p) > 0} class="mt-1 text-xs font-medium text-success">
                {gettext("Keeps %{count} record(s) you entered by hand.",
                  count: preserved_total(p)
                )}
              </div>
              <div :if={p.preserves_fields != []} class="mt-1 text-xs text-base-content/70">
                {gettext("Keeps: %{fields}",
                  fields: Enum.map_join(p.preserves_fields, ", ", &field_label/1)
                )}
              </div>
              <div :if={p.bibliography_adds != []} class="mt-1 text-xs text-base-content/70">
                {gettext("Adds %{count} reference(s) to the bibliography:",
                  count: length(p.bibliography_adds)
                )}
                <ul class="ml-4 list-disc">
                  <li :for={citation <- p.bibliography_adds}>{citation}</li>
                </ul>
              </div>
              <div :if={p.bibliography_skips != []} class="mt-1 text-xs text-warning">
                {gettext("Skips %{count} reference(s) Playcode cannot store:",
                  count: length(p.bibliography_skips)
                )}
                <ul class="ml-4 list-disc">
                  <li :for={citation <- p.bibliography_skips}>{citation}</li>
                </ul>
              </div>
              <div class="mt-1 text-xs">
                {gettext("Numbering: %{rule}", rule: p.numbering)}
              </div>
              <div :if={p.split_verses != []} class="mt-1 text-xs text-warning">
                {ngettext(
                  "%{count} part of a split verse out of order:",
                  "%{count} parts of split verses out of order:",
                  length(p.split_verses)
                )}
                <ul class="ml-4 list-disc">
                  <li :for={part <- p.split_verses}>
                    <code>{part.line_id || "?"}</code>
                    “{part.text}”, {PlayLabels.split_verse_problem(part.problem, part.part)}
                  </li>
                </ul>
              </div>
            </li>
          </ul>

          <form
            :if={edits_unconfirmed?(@previews, false)}
            id="overwrite-edits-form"
            phx-change="overwrite_edits"
            class="mt-4"
          >
            <label class="label cursor-pointer justify-start gap-2 text-sm font-medium text-warning">
              <input
                type="checkbox"
                name="overwrite_edits"
                value="true"
                checked={@overwrite_edits}
                class="checkbox checkbox-warning checkbox-sm"
              />
              {gettext("Replace the rows edited by hand too")}
            </label>
          </form>

          <div class="card-actions mt-4">
            <button
              phx-click="confirm_import"
              class="btn btn-primary btn-sm"
              disabled={edits_unconfirmed?(@previews, @overwrite_edits)}
            >
              {if existing_count(@previews) > 0,
                do: gettext("Replace and import"),
                else: gettext("Import")}
            </button>
            <button phx-click="cancel_import" class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </button>
          </div>
        </div>
      </div>

      <%!-- Import progress --%>
      <div
        :if={@phase == :importing}
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <div class="flex items-center gap-3">
            <span class="loading loading-spinner loading-md text-primary"></span>
            <span class="font-medium">
              {gettext("Importing file %{done} of %{total}...",
                done: @import_done + 1,
                total: @import_total
              )}
            </span>
          </div>
          <progress
            value={@import_done}
            max={@import_total}
            class="progress progress-primary w-full mt-2"
          />
        </div>
      </div>

      <%!-- Success results --%>
      <div
        :if={@successes != [] && @phase == :idle}
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title">{gettext("Imported Plays")}</h2>
          <div
            class="overflow-x-auto"
            tabindex="0"
            role="region"
            aria-label={gettext("Imported Plays")}
          >
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("File")}</th>
                  <th>{gettext("Title")}</th>
                  <th>{gettext("Code")}</th>
                  <th>{gettext("Schema")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={{filename, title, code, play_id, warnings} <- @successes}>
                  <td class="font-mono text-xs">{filename}</td>
                  <td>{title}</td>
                  <td>
                    <span class="badge badge-primary badge-sm">{code}</span>
                  </td>
                  <td>
                    <%= if warnings == [] do %>
                      <span class="badge badge-success badge-sm gap-1">
                        <.icon name="hero-check-mini" class="size-3" />
                        {gettext("Valid")}
                      </span>
                    <% else %>
                      <details>
                        <summary class="badge badge-warning badge-sm gap-1 cursor-pointer">
                          <.icon name="hero-exclamation-triangle-mini" class="size-3" />
                          {gettext("%{count} warning(s)", count: length(warnings))}
                        </summary>
                        <ul
                          class="mt-2 ml-2 text-xs font-mono text-base-content/70 space-y-1 max-h-40 overflow-y-auto"
                          tabindex="0"
                          aria-label={gettext("%{count} warning(s)", count: length(warnings))}
                        >
                          <li :for={w <- Enum.take(warnings, 10)}>{w}</li>
                          <li :if={length(warnings) > 10} class="text-base-content/70">
                            … {gettext("and %{count} more", count: length(warnings) - 10)}
                          </li>
                        </ul>
                      </details>
                    <% end %>
                  </td>
                  <td class="flex gap-1">
                    <.link
                      navigate={~p"/admin/plays/#{play_id}"}
                      class="btn btn-ghost btn-xs tooltip"
                      aria-label={gettext("Edit in Admin")}
                      data-tip={gettext("Edit in Admin")}
                    >
                      <.icon name="hero-pencil-square-mini" class="size-4" />
                    </.link>
                    <.link
                      href={~p"/plays/#{code}"}
                      target="_blank"
                      class="btn btn-ghost btn-xs tooltip"
                      aria-label={gettext("Preview")}
                      data-tip={gettext("Preview")}
                    >
                      <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" />
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="card-actions mt-4">
            <.link navigate={~p"/admin/plays"} class="btn btn-sm btn-outline">
              {gettext("View all plays")}
            </.link>
          </div>
        </div>
      </div>
    </.page>
    """
  end

  defp existing_count(previews), do: Enum.count(previews, & &1.existing)

  # A file whose rows were edited by hand since their import, not yet ticked for replacing.
  defp edits_unconfirmed?(previews, overwrite_edits),
    do: not overwrite_edits and Enum.any?(previews, &(&1.edited > 0))

  defp tei_total(preview), do: TeiImport.mixed_ownership_total(preview.replaces)
  defp preserved_total(preview), do: TeiImport.mixed_ownership_total(preview.preserves)

  defp field_label(:language), do: gettext("language")
  defp field_label(:relationship_type), do: gettext("relationship")
  defp field_label(:parent_play_id), do: gettext("parent play")
  defp field_label(:is_complete), do: gettext("completeness")
  defp field_label(:show_variants), do: gettext("variant readings")
  defp field_label(:team_note), do: gettext("team note")
  defp field_label(:historical_time), do: gettext("historical time")
  defp field_label(:historical_time_note), do: gettext("historical time note")
  defp field_label(:composition_date_from), do: gettext("composition date (from)")
  defp field_label(:composition_date_to), do: gettext("composition date (to)")
  defp field_label(:composition_date_note), do: gettext("composition date note")
  defp field_label(:form), do: gettext("form")

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .xml files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files (max 20)")
  defp upload_error_to_string(err), do: "#{gettext("Error")}: #{inspect(err)}"

  defp import_label(0), do: gettext("Import")
  defp import_label(n), do: ngettext("Import %{count} file", "Import %{count} files", n)
end
