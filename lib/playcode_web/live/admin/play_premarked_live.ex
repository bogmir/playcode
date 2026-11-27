defmodule PlaycodeWeb.Admin.PlayPremarkedLive do
  @moduledoc """
  /admin/plays/:id/premarked: a premarked text, pasted or read from its .docx, beside the
  play it would make (`WordParser.draft/2`), with what is wrong line by line; the import
  replaces the play's text with it. Only while the play is a draft. The text lives in the
  page (and the browser's storage, through the `PremarkedText` hook) until imported.
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.PlayText, only: [play_body: 1]

  alias Playcode.Catalogue
  alias Playcode.Import.WordParser
  alias Playcode.PlayContent.{Element, SplitVerses}

  @max_bytes 5_000_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play_with_all!(id)

    if play.is_complete do
      {:ok,
       socket
       |> put_flash(:error, gettext("A complete play's text is not replaced from Word."))
       |> push_navigate(to: ~p"/admin/plays/#{play.id}")}
    else
      {:ok,
       socket
       |> assign(:page_title, "#{play.title} — #{gettext("Premarked text")}")
       |> assign(:play, play)
       |> assign(:play_context, %{play: play, active_tab: :premarked})
       |> allow_upload(:docx,
         accept: ~w(.docx),
         max_entries: 1,
         max_file_size: 10_000_000,
         auto_upload: true,
         progress: &read_docx/3
       )
       |> preview("")}
    end
  end

  @impl true
  def handle_event("preview", %{"text" => text}, socket), do: {:noreply, preview(socket, text)}

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("import", %{"text" => text}, socket) do
    socket = preview(socket, text)
    play = socket.assigns.play

    case socket.assigns.draft &&
           WordParser.import_content(play.id, WordParser.paragraphs_from_text(text)) do
      {:ok, _play} ->
        {:noreply,
         socket
         |> push_event("premarked:clear", %{})
         |> put_flash(:info, gettext("Content imported successfully."))
         |> push_navigate(to: ~p"/admin/plays/#{play.id}")}

      _not_imported ->
        {:noreply, put_flash(socket, :error, gettext("The text was not imported."))}
    end
  end

  defp read_docx(:docx, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, WordParser.paragraphs(path)}
        end)

      case result do
        {:ok, paragraphs} ->
          text = Enum.join(paragraphs, "\n")
          {:noreply, socket |> push_event("premarked:fill", %{text: text}) |> preview(text)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Only .docx files are accepted."))}
      end
    else
      {:noreply, socket}
    end
  end

  defp preview(socket, text) do
    cond do
      String.trim(text) == "" ->
        assign(socket, draft: nil, too_long?: false)

      byte_size(text) > @max_bytes ->
        assign(socket, draft: nil, too_long?: true)

      true ->
        {:ok, draft} =
          WordParser.draft(WordParser.paragraphs_from_text(text), socket.assigns.play)

        assign(socket,
          draft: draft,
          too_long?: false,
          leads: draft.divisions |> Element.verse_lines() |> SplitVerses.leads(),
          marks: marks(draft)
        )
    end
  end

  defp marks(draft) do
    flagged = MapSet.new(draft.warnings ++ draft.errors, & &1.line)
    Map.new(draft.lines, fn {id, line} -> {id, %{line: line, warn: line in flagged}} end)
  end

  defp importable?(nil), do: false
  defp importable?(draft), do: draft.errors == []

  defp message(:untagged), do: gettext("A line with no tag, stored as unrecognised")

  defp message(:unknown_tag),
    do: gettext("A tag Playcode does not know, left in the text as typed")

  defp message(:dropped_text), do: gettext("Text before the line's first tag, which is lost")

  defp message(:part_without_initial),
    do: gettext("A middle or final part with no initial part before it")

  defp message(:initial_unfinished), do: gettext("An initial part no final part closes")
  defp message(:speaker_as_words), do: gettext("A speaker's name tagged as words")
  defp message(:end_marker), do: gettext("An end marker, stored as an unrecognised line")
  defp message(:unclosed_aside), do: gettext("(( with no )): the aside is not read")
  defp message(:refused), do: gettext("Markup Playcode cannot store: correct it to import")

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :notices, :list, required: true
  attr :class, :string, required: true

  defp notices(assigns) do
    ~H"""
    <ul id={@id} aria-label={@label} class="mb-3 grid max-h-44 gap-1 overflow-y-auto">
      <li :for={notice <- @notices}>
        <button
          type="button"
          data-line={notice.line}
          class={[
            "grid w-full grid-cols-[5.5em_1fr] gap-2 rounded border px-2 py-1 text-left text-sm",
            @class
          ]}
        >
          <span class="font-semibold whitespace-nowrap">
            {gettext("line %{number}", number: notice.line + 1)}
          </span>
          <span>
            {message(notice.kind)}:
            <q class="text-base-content/70">{String.slice(notice.text, 0, 60)}</q>
          </span>
        </button>
      </li>
    </ul>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_header>
        {gettext("Premarked text")}
        <:subtitle>
          {gettext(
            "Paste the premarked text or drop the .docx: beside it, the play as it would be stored. Nothing is stored until you import."
          )}
        </:subtitle>
      </.page_header>

      <div class="grid gap-4 lg:grid-cols-2 lg:items-start">
        <section
          class="card border border-base-300 bg-base-100 p-3"
          aria-labelledby="premarked-text-label"
        >
          <form id="premarked-form" phx-change="preview" phx-submit="import">
            <label
              id="premarked-text-label"
              for="premarked-text"
              class="mb-1 block text-sm font-semibold"
            >
              {gettext("Premarked text")}
            </label>
            <textarea
              id="premarked-text"
              name="text"
              phx-debounce="400"
              phx-hook="PremarkedText"
              phx-update="ignore"
              data-play={@play.id}
              spellcheck="false"
              class="textarea h-[32rem] w-full resize-y font-mono text-xs leading-relaxed"
            ></textarea>
          </form>

          <form id="premarked-upload" phx-change="validate_upload" class="mt-2">
            <.drop_zone upload={@uploads.docx} label={gettext("Or drop the premarked .docx here")} />
          </form>

          <details class="mt-2 rounded border border-base-300 px-3 py-2 text-sm">
            <summary class="cursor-pointer font-semibold">{gettext("The tags")}</summary>
            <dl class="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
              <dt class="font-mono text-primary">{"{a}"}</dt>
              <dd>{gettext("act (or untagged: “JORNADA I”, “ACTO PRIMERO”)")}</dd>
              <dt class="font-mono text-primary">{"{e}"}</dt>
              <dd>{gettext("scene")}</dd>
              <dt class="font-mono text-primary">{"{p}"}</dt>
              <dd>{gettext("speaker")}</dd>
              <dt class="font-mono text-primary">{"{v}"}</dt>
              <dd>{gettext("verse")}</dd>
              <dt class="font-mono text-primary">{"{ti} {tm} {tf}"}</dt>
              <dd>{gettext("initial, middle and final parts of a verse split between speakers")}</dd>
              <dt class="font-mono text-primary">{"{m}"}</dt>
              <dd>{gettext("stanza")}</dd>
              <dt class="font-mono text-primary">{"{pr}"}</dt>
              <dd>{gettext("prose")}</dd>
              <dt class="font-mono text-primary">{"{ac}"}</dt>
              <dd>{gettext("stage direction")}</dd>
              <dt class="font-mono text-primary">{"{ap}"}</dt>
              <dd>
                {gettext("aside: the whole paragraph, or how it is said (“(Aparte)”) before ((…))")}
              </dd>
              <dt class="font-mono text-primary">((…))</dt>
              <dd>{gettext("the words said aside within a speech")}</dd>
              <dt class="font-mono text-primary">&lt;&lt;…&gt;&gt;</dt>
              <dd>{gettext("italics")}</dd>
            </dl>
          </details>
        </section>

        <section
          class="card border border-base-300 bg-base-100 p-3"
          aria-labelledby="premarked-preview-label"
        >
          <h2 id="premarked-preview-label" class="mb-2 text-sm font-semibold">
            {gettext("The play as it would be stored")}
          </h2>

          <p :if={@too_long?} class="text-sm text-error">
            {gettext("The text is too long to read.")}
          </p>

          <div :if={@draft} id="premarked-summary" class="mb-2 text-sm">
            <p class="flex flex-wrap gap-x-4">
              <span>{ngettext("1 act", "%{count} acts", @draft.summary.acts)}</span>
              <span>{ngettext("1 scene", "%{count} scenes", @draft.summary.scenes)}</span>
              <span>{ngettext("1 verse", "%{count} verses", @draft.summary.verses)}</span>
            </p>
            <ul aria-label={gettext("Speeches by speaker")} class="mt-1 flex flex-wrap gap-1">
              <li
                :for={{speaker, count} <- @draft.summary.speakers}
                class={[
                  "badge badge-sm max-w-64 gap-1",
                  count == 1 && "badge-warning badge-outline"
                ]}
                title={speaker}
              >
                <span class="truncate">{speaker}</span>
                <span class="text-base-content/70">{count}</span>
              </li>
            </ul>
          </div>

          <.notices
            :if={@draft && @draft.errors != []}
            id="premarked-errors"
            label={gettext("Errors")}
            notices={@draft.errors}
            class="border-error/60 bg-error/10"
          />
          <.notices
            :if={@draft && @draft.warnings != []}
            id="premarked-warnings"
            label={gettext("Warnings")}
            notices={@draft.warnings}
            class="border-warning/60 bg-warning/10"
          />
          <p
            :if={@draft && @draft.warnings == []}
            id="premarked-warnings"
            class="mb-2 text-sm text-success"
          >
            {gettext("No warnings.")}
          </p>

          <div
            id="premarked-preview"
            tabindex="0"
            role="region"
            aria-labelledby="premarked-preview-label"
            class="premarked-preview h-[32rem] overflow-y-auto rounded border border-base-300 bg-base-200 py-2 pr-3 pl-6"
          >
            <.play_body
              :if={@draft}
              divisions={@draft.divisions}
              paratexts={@draft.paratexts}
              leads={@leads}
              lines={@marks}
            />
          </div>
        </section>
      </div>

      <div class="mt-4 flex flex-wrap items-center gap-4">
        <button
          id="premarked-import"
          type="submit"
          form="premarked-form"
          class="btn btn-primary"
          disabled={not importable?(@draft)}
        >
          {gettext("Import and replace the text")}
        </button>
        <p class="max-w-prose text-sm text-base-content/80">
          {gettext(
            "Replaces the play's text, its characters and their notes. Keeps the play's details, editors, sources, bibliography, witnesses, places, performances and the paratexts typed by hand. Warnings do not stop the import: an unrecognised line is stored, to correct in the content editor."
          )}
        </p>
      </div>
    </.page>
    """
  end
end
