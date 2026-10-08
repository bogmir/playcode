defmodule PlaycodeWeb.Admin.FilemakerSyncLive do
  @moduledoc """
  /admin/filemaker: upload the FileMaker export, preview what `FilemakerSync.plan/3` would
  change, tick the conflicts to overwrite, and apply. Admins only.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Import.Filemaker
  alias Playcode.Import.FilemakerSync
  alias PlaycodeWeb.PlayLabels

  # Stricter than the live_session's :view_admin, declared here so admin
  # sections still navigate without a full page reload.
  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :import_filemaker}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("FileMaker sync"))
     |> assign(:plan, nil)
     |> assign(:plays_by_id, %{})
     |> assign(:selected, MapSet.new())
     |> assign(:results, nil)
     |> allow_upload(:export,
       accept: ~w(.ndjson),
       max_entries: 1,
       max_file_size: 20_000_000
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :export, ref)}
  end

  def handle_event("preview", _params, socket) do
    if Enum.all?(socket.assigns.uploads.export.entries, & &1.done?) do
      case consume_uploaded_entries(socket, :export, fn %{path: path}, _entry ->
             {:ok, read_plan(path)}
           end) do
        [] ->
          {:noreply, socket}

        [{:ok, plan, plays}] ->
          {:noreply,
           socket
           |> assign(:plan, plan)
           |> assign(:plays_by_id, Map.new(plays, &{&1.id, &1}))
           |> assign(:selected, MapSet.new())
           |> assign(:results, nil)}

        [{:error, reason}] ->
          {:noreply, put_flash(socket, :error, error_message(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("discard", _params, socket) do
    {:noreply,
     socket
     |> assign(:plan, nil)
     |> assign(:plays_by_id, %{})
     |> assign(:selected, MapSet.new())
     |> assign(:results, nil)}
  end

  # The key is {play_id, field-as-string} because phx-value-* arrives as strings.
  def handle_event("toggle-conflict", %{"play-id" => play_id, "field" => field}, socket) do
    key = {play_id, field}

    selected =
      if MapSet.member?(socket.assigns.selected, key) do
        MapSet.delete(socket.assigns.selected, key)
      else
        MapSet.put(socket.assigns.selected, key)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  # ponytail: the plan is held in assigns, so it can go stale if someone else
  # edits a play between preview and Apply. Single-curator tool; re-plan on
  # Apply if that stops being true.
  #
  # The ticked set *is* the force list. Narrowing plan.conflicts before handing it
  # over is what makes per-conflict force free: an empty selection folds nothing
  # in, which is exactly force: false.
  def handle_event("apply", _params, socket) do
    %{plan: plan, selected: selected} = socket.assigns

    results =
      %{plan | conflicts: Enum.filter(plan.conflicts, &selected?(&1, selected))}
      |> FilemakerSync.apply_plan(user_id: socket.assigns.current_user.id, force: true)

    written = Enum.count(results, &match?({:ok, _code}, &1))

    {:noreply,
     socket
     |> assign(:results, results)
     |> assign(:plan, nil)
     |> assign(:selected, MapSet.new())
     |> put_flash(:info, gettext("Updated %{count} play(s).", count: written))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("FileMaker sync")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Upload the FileMaker export, review what it would change, then apply it.")}
        </p>
      </div>

      <div
        :if={is_nil(@plan) && is_nil(@results)}
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title">{gettext("Select the export")}</h2>
          <p class="mb-3 text-sm text-base-content/70">
            {gettext("One .ndjson file, as exported from FileMaker.")}
          </p>
          <form id="upload-form" phx-submit="preview" phx-change="validate">
            <.live_file_input
              upload={@uploads.export}
              class="file-input file-input-bordered w-full mb-4"
            />

            <div :for={err <- upload_errors(@uploads.export)} class="text-error text-sm mb-2">
              {upload_error_to_string(err)}
            </div>

            <button type="submit" class="btn btn-primary" disabled={@uploads.export.entries == []}>
              {gettext("Preview changes")}
            </button>
          </form>
        </div>
      </div>

      <div
        :if={@plan && @plan.changes != []}
        id="changes"
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title">
            {gettext("%{count} play(s) to update", count: length(@plan.changes))}
          </h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Code")}</th>
                  <th>{gettext("Title")}</th>
                  <th>{gettext("Changes")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={change <- @plan.changes}>
                  <td><span class="badge badge-primary badge-sm">{change.code}</span></td>
                  <td>{change.title}</td>
                  <td>
                    <ul class="space-y-0.5">
                      <li :for={{field, value} <- change.sets} class="text-xs">
                        <span class="font-medium">{field_label(field)}</span>:
                        <span class="text-base-content/60">
                          {current_value(@plays_by_id, change.play_id, field)}
                        </span>
                        <span aria-hidden="true">&rarr;</span>
                        <span class="font-medium">{value_label(field, value, @plays_by_id)}</span>
                      </li>
                    </ul>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div
        :if={@plan && @plan.conflicts != []}
        id="conflicts"
        class="card mb-6 border border-warning bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title text-warning">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            {gettext("%{count} value(s) already set by a researcher",
              count: length(@plan.conflicts)
            )}
          </h2>
          <p class="text-sm text-base-content/70">
            {gettext(
              "These are left alone unless you tick them. For research metadata the export is a starting point, not the authority."
            )}
          </p>

          <ul class="mt-3 space-y-2">
            <li :for={conflict <- @plan.conflicts} class="rounded-box bg-base-200 px-3 py-2">
              <label class="flex items-start gap-3 cursor-pointer">
                <input
                  type="checkbox"
                  class="checkbox checkbox-warning checkbox-sm mt-0.5"
                  checked={selected?(conflict, @selected)}
                  phx-click="toggle-conflict"
                  phx-value-play-id={conflict.play_id}
                  phx-value-field={conflict.field}
                />
                <span class="min-w-0">
                  <span class="badge badge-primary badge-sm">{conflict.code}</span>
                  <span class="font-medium">{conflict.title}</span>
                  <span class="block text-xs mt-1">
                    <span class="font-medium">{field_label(conflict.field)}</span>: {gettext(
                      "keep %{current}",
                      current: value_label(conflict.field, conflict.current, @plays_by_id)
                    )} — {gettext("the export says %{indexed}",
                      indexed: value_label(conflict.field, conflict.indexed, @plays_by_id)
                    )}
                  </span>
                </span>
              </label>
            </li>
          </ul>
        </div>
      </div>

      <div
        :if={@plan && (@plan.unchanged != [] or @plan.missing != [] or @plan.skipped != [])}
        id="counts"
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body gap-2">
          <details :if={@plan.unchanged != []} id="unchanged">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} play(s) already match", count: length(@plan.unchanged))}
            </summary>
            <p class="mt-2 font-mono text-xs text-base-content/70">
              {Enum.join(@plan.unchanged, ", ")}
            </p>
          </details>

          <details :if={@plan.missing != []} id="missing">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} play(s) are not in the published index",
                count: length(@plan.missing)
              )}
            </summary>
            <p class="mt-2 text-xs text-base-content/70">
              {gettext(
                "Nothing is created for these. A play can be absent from the index and still have research metadata to fill, in which case it is listed above as well."
              )}
            </p>
            <p class="mt-1 font-mono text-xs text-base-content/70">
              {Enum.join(@plan.missing, ", ")}
            </p>
          </details>

          <details :if={@plan.skipped != []} id="skipped">
            <summary class="cursor-pointer text-sm">
              {gettext("%{count} dating(s) not imported", count: length(@plan.skipped))}
            </summary>
            <p class="mt-2 text-xs text-base-content/70">
              {gettext(
                "The export gives no usable years for these — an implausible span, or a header with no date in it. Nothing is written and there is nothing to tick: enter the dating by hand if you have it."
              )}
            </p>
            <ul class="mt-1 space-y-1 font-mono text-xs text-base-content/70">
              <li :for={skipped <- @plan.skipped}>{skipped.code}: {skipped.value}</li>
            </ul>
          </details>
        </div>
      </div>

      <div :if={@plan} id="sync-actions" class="flex items-center gap-3">
        <p
          :if={@plan.changes == [] and @plan.conflicts == []}
          class="text-sm text-base-content/70"
        >
          {gettext("Everything already matches the export.")}
        </p>
        <button
          :if={@plan.changes != [] or @plan.conflicts != []}
          phx-click="apply"
          class="btn btn-primary"
        >
          {gettext("Apply")}
        </button>
        <button phx-click="discard" class="btn btn-ghost">{gettext("Discard")}</button>
      </div>

      <div :if={@results} id="results" class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Applied")}</h2>
          <ul class="space-y-1 text-sm">
            <li :for={result <- @results}>
              <%= case result do %>
                <% {:ok, code} -> %>
                  <span class="badge badge-success badge-sm">{code}</span>
                <% {:error, code, changeset} -> %>
                  <span class="badge badge-error badge-sm">{code}</span>
                  <span class="ml-2 text-xs text-error">{inspect(changeset.errors)}</span>
              <% end %>
            </li>
          </ul>
          <div class="card-actions mt-4">
            <button phx-click="discard" class="btn btn-sm btn-outline">
              {gettext("Sync another export")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp upload_error_to_string(:too_large), do: gettext("File is too large (max 20MB)")
  defp upload_error_to_string(:not_accepted), do: gettext("Only .ndjson files are accepted")
  defp upload_error_to_string(:too_many_files), do: gettext("Upload one file at a time")
  defp upload_error_to_string(err), do: "#{gettext("Error")}: #{inspect(err)}"

  # ponytail: synchronous. 649 lines parsed, 82 plays diffed in memory, ~11 rows
  # written. start_async if the export grows an order of magnitude.
  defp read_plan(path) do
    with {:ok, index} <- Filemaker.load_index(path),
         {:ok, versions} <- Filemaker.load_versions(path),
         true <- map_size(index) > 0 or map_size(versions) > 0 do
      plays = FilemakerSync.all_plays()
      {:ok, FilemakerSync.plan(index, plays, versions), plays}
    else
      false -> {:error, :no_records}
      {:error, reason} -> {:error, reason}
    end
  end

  defp error_message(:no_records) do
    gettext("No FileMaker records found in that file. Is it the right export?")
  end

  defp error_message({:malformed_record, record}) do
    gettext("Cannot read the file: record %{record} is malformed.", record: record)
  end

  defp error_message(reason) do
    "#{gettext("Cannot read the file")}: #{inspect(reason)}"
  end

  @doc """
  The human name of a field in a plan's `sets`.

  The catch-all clause is deliberate: a later FileMaker slice adds a field to
  `Filemaker.load_versions/1` and therefore to `sets`, and it must render on this
  page without an edit here. Adding a clause is polish, not a requirement.
  """
  def field_label(:language), do: gettext("Language")
  def field_label(:relationship_type), do: gettext("Relationship")
  def field_label(:parent_play_id), do: gettext("Parent play")
  def field_label(:historical_time), do: gettext("Historical time")
  def field_label(:historical_time_note), do: gettext("Historical time note")
  def field_label(:composition_date_from), do: gettext("Composition Date (from)")
  def field_label(:composition_date_to), do: gettext("Composition Date (to)")
  # The admin form already translates this msgid; reuse it rather than add a second
  # msgid with the same msgstr.
  def field_label(:composition_date_note), do: gettext("Composition Date Note")
  def field_label(other), do: other |> to_string() |> String.replace("_", " ")

  @doc "The display value of a field, given the plays keyed by id."
  # Blank takes priority over every field-specific clause below: a play with no
  # parent must read the same "(blank)" whether it is the current value or the
  # value a change sets, not "—" for one side and "" (PlayLabels' catch-all) for
  # the other.
  def value_label(_field, blank, _plays) when blank in [nil, ""], do: gettext("(blank)")
  def value_label(:historical_time, value, _plays), do: PlayLabels.historical_time_label(value)

  def value_label(:parent_play_id, id, plays) do
    case Map.get(plays, id) do
      nil -> "—"
      play -> play.code
    end
  end

  def value_label(_field, value, _plays), do: to_string(value)

  defp current_value(plays_by_id, play_id, field) do
    value_label(field, plays_by_id |> Map.fetch!(play_id) |> Map.get(field), plays_by_id)
  end

  defp selected?(conflict, selected) do
    MapSet.member?(selected, {conflict.play_id, to_string(conflict.field)})
  end
end
