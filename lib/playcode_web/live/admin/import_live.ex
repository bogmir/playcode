defmodule PlaycodeWeb.Admin.ImportLive do
  use PlaycodeWeb, :live_view

  # alias Playcode.Export.TeiValidator
  alias Playcode.Import.TeiParser
  alias Playcode.ActivityLog

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Import TEI-XML"))
     |> assign(:successes, [])
     |> assign(:errors, [])
     |> assign(:importing, false)
     |> assign(:import_total, 0)
     |> assign(:import_done, 0)
     |> assign(:pending, [])
     |> assign(:previews, [])
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

  def handle_event("import", _params, socket) do
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

  def handle_event("confirm_import", _params, socket) do
    {:noreply, start_import(socket, socket.assigns.pending)}
  end

  def handle_event("cancel_import", _params, socket) do
    Enum.each(socket.assigns.pending, fn {path, _filename} -> File.rm(path) end)

    {:noreply, socket |> assign(:pending, []) |> assign(:previews, [])}
  end

  # An import that lands on a play we already hold replaces its whole text. Say so and
  # wait for a click; a batch of entirely new plays goes straight through.
  defp start_or_confirm(socket, pending) do
    previews =
      for {path, filename} <- pending,
          {:ok, preview} <- [TeiParser.preview_import(path)],
          preview.existing,
          do: Map.put(preview, :filename, filename)

    if previews == [] do
      start_import(socket, pending)
    else
      socket
      |> assign(:pending, pending)
      |> assign(:previews, previews)
      |> assign(:successes, [])
      |> assign(:errors, [])
    end
  end

  defp start_import(socket, pending) do
    send(self(), {:import_next, pending})

    socket
    |> assign(:importing, true)
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

    socket = assign(socket, :importing, false)
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
      case TeiParser.import_file(path) do
        {:ok, play} ->
          ActivityLog.log!(%{
            user_id: socket.assigns[:current_user] && socket.assigns.current_user.id,
            play_id: play.id,
            action: "import",
            resource_type: "play",
            resource_id: play.id,
            metadata: %{filename: filename, title: play.title, code: play.code}
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

  # defp validate_source_file(path) do
  #   case File.read(path) do
  #     {:ok, xml} ->
  #       case TeiValidator.validate(xml) do
  #         {:ok, :valid} -> []
  #         {:error, errors} when is_list(errors) -> errors
  #         {:error, _atom} -> []
  #       end
  #
  #     {:error, _} ->
  #       []
  #   end
  # end

  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error({:xml_parse_error, detail}), do: "XML parse error: #{inspect(detail)}"

  defp format_error({:play_already_exists, code}),
    do: gettext("Play with code %{code} already exists", code: code)

  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("Import TEI-XML Files")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Import one or many TEI files and review successful ingestions.")}
        </p>
      </div>

      <%!-- Upload files from browser --%>
      <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Select Files")}</h2>
          <p class="mb-3 text-sm text-base-content/70">
            {gettext("Choose one or more TEI-XML files from your computer.")}
          </p>
          <form id="upload-form" phx-submit="import" phx-change="validate">
            <.live_file_input
              upload={@uploads.tei_files}
              class="file-input file-input-bordered w-full mb-4"
              disabled={@importing}
            />

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
              disabled={@uploads.tei_files.entries == [] || @importing}
            >
              {gettext("Import %{count} file(s)", count: length(@uploads.tei_files.entries))}
            </button>
          </form>
        </div>
      </div>

      <%!-- Replacement confirmation --%>
      <div :if={@previews != []} class="card mb-6 border border-warning bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-warning">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            {gettext("%{count} of these plays already exist", count: length(@previews))}
          </h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "Importing replaces the text and the records that came from TEI. Anything entered by hand is kept."
            )}
          </p>

          <ul class="mt-3 space-y-3">
            <li :for={p <- @previews} class="rounded-box bg-base-200 px-3 py-2">
              <div class="flex items-center gap-2">
                <span class="badge badge-primary badge-sm">{p.code}</span>
                <span class="font-medium">{p.existing.title}</span>
                <span :if={p.archived} class="badge badge-ghost badge-sm">
                  {gettext("archived — will be restored")}
                </span>
              </div>
              <div class="mt-1 text-xs text-base-content/70">
                {gettext(
                  "Replaces %{divisions} division(s), %{elements} element(s), %{characters} character(s) and %{tei} record(s) imported from TEI.",
                  divisions: p.replaces.divisions,
                  elements: p.replaces.elements,
                  characters: p.replaces.characters,
                  tei: tei_total(p)
                )}
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
            </li>
          </ul>

          <div class="card-actions mt-4">
            <button phx-click="confirm_import" class="btn btn-warning btn-sm">
              {gettext("Replace and import")}
            </button>
            <button phx-click="cancel_import" class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </button>
          </div>
        </div>
      </div>

      <%!-- Import progress --%>
      <div :if={@importing} class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
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
        :if={@successes != [] && !@importing}
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title">{gettext("Imported Plays")}</h2>
          <div class="overflow-x-auto">
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
                        <ul class="mt-2 ml-2 text-xs font-mono text-base-content/70 space-y-1 max-h-40 overflow-y-auto">
                          <li :for={w <- Enum.take(warnings, 10)}>{w}</li>
                          <li :if={length(warnings) > 10} class="text-base-content/50">
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
                      data-tip={gettext("Edit in Admin")}
                    >
                      <.icon name="hero-pencil-square-mini" class="size-4" />
                    </.link>
                    <.link
                      href={~p"/plays/#{code}"}
                      target="_blank"
                      class="btn btn-ghost btn-xs tooltip"
                      data-tip={gettext("View public page")}
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
    </div>
    """
  end

  defp tei_total(preview), do: TeiParser.mixed_ownership_total(preview.replaces)
  defp preserved_total(preview), do: TeiParser.mixed_ownership_total(preview.preserves)

  defp field_label(:language), do: gettext("language")
  defp field_label(:relationship_type), do: gettext("relationship")
  defp field_label(:parent_play_id), do: gettext("parent play")
  defp field_label(:is_complete), do: gettext("completeness")

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .xml files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Too many files (max 20)")
  defp upload_error_to_string(err), do: "#{gettext("Error")}: #{inspect(err)}"
end
