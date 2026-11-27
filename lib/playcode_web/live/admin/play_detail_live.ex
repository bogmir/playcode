defmodule PlaycodeWeb.Admin.PlayDetailLive do
  @moduledoc """
  /admin/plays/:id: a play's overview: its structure and statistics, its downloads, the
  completeness switch that decides whether it is published, TEI validation, and the Word
  import that replaces its text.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.Export.TeiValidator
  alias Playcode.Export.TeiXml
  alias Playcode.PlayContent
  alias Playcode.PlayContent.InlineMarkup
  alias Playcode.Statistics
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.Components.PlayText
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
     |> assign(:derived, Catalogue.list_derived(play))
     |> assign(:siblings, siblings(play))
     |> assign(:divisions, divisions)
     |> assign(:statistic, statistic)
     |> assign(:play_context, %{play: play, active_tab: :overview})
     |> assign(:validation_result, nil)
     |> assign(:validating, false)}
  end

  @impl true
  def handle_event("validate_tei", _, socket) do
    play = socket.assigns.play
    xml = TeiXml.generate(play)
    result = TeiValidator.validate(xml)

    {:noreply, assign(socket, validation_result: result, validating: false)}
  end

  def handle_event("archive", _, socket) do
    play = socket.assigns.play

    LiveHelpers.log_activity(socket, "delete", "play", play.id, %{
      title: play.title,
      code: play.code,
      archived: true
    })

    {:ok, _} = Catalogue.delete_play(play)

    {:noreply, push_navigate(socket, to: ~p"/admin/plays")}
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

  # One change of the file's revision history on a line: "2021 · Muñoz Pons, Carlos · Revisión…".
  defp revision(change) do
    [change.date, change.people, change.description, change.note]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
    |> InlineMarkup.plain()
  end

  # A top-level division's whole verses, its scenes' included.
  defp siblings(%Play{parent_play: %Play{} = parent, id: id}),
    do: parent |> Catalogue.list_derived() |> Enum.reject(&(&1.id == id))

  defp siblings(_play), do: []

  defp original_line(original) do
    status = if original.is_complete, do: gettext("Complete"), else: gettext("Draft")
    Enum.join(Enum.reject([original.author_name, status], &is_nil/1), " · ")
  end

  # "into French" only when the play leaves its original's language.
  defp into_language(%Play{parent_play: %Play{language: from}, language: to}) when from != to,
    do: PlayLabels.into_language_label(to)

  defp into_language(_play), do: nil

  # The derived plays come in `Catalogue.family_order/1`, so each kind is one run.
  defp by_kind(plays), do: Enum.chunk_by(plays, & &1.relationship_type)

  defp kind_counts(plays),
    do:
      Enum.map_join(by_kind(plays), " · ", fn [play | _] = kind ->
        PlayLabels.kind_count_label(play.relationship_type, length(kind))
      end)

  attr :plays, :list, required: true

  defp family(assigns) do
    ~H"""
    <div :for={[first | _] = kind <- by_kind(@plays)} class="mt-2">
      <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
        {PlayLabels.relationship_group_label(first.relationship_type)}
      </p>
      <ul class="mt-1 space-y-0.5">
        <li :for={play <- kind} class="flex items-baseline gap-1.5">
          <span :if={play.language} class="badge badge-sm shrink-0 border-0 bg-base-300 font-mono">
            {String.upcase(play.language)}
          </span>
          <span class="min-w-0">
            <.link navigate={~p"/admin/plays/#{play.id}"} class="link link-hover text-primary">
              {play.title}
            </.link>
            <span class="whitespace-nowrap font-mono text-xs text-base-content/70">
              {Play.short_code(play.code)}
            </span>
          </span>
        </li>
      </ul>
    </div>
    """
  end

  defp act_verses(nil, _division), do: nil

  defp act_verses(statistic, division),
    do: Enum.find_value(statistic.data["divisions"], &(&1["id"] == division.id && &1["verses"]))

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
          · {Playcode.Catalogue.Play.language_name(@play.language)}
          <span :if={form = Playcode.Catalogue.Play.form(@play)}>
            · {PlayLabels.form_label(form)}
          </span>
        </:subtitle>
        <:actions>
          <.download_group
            base={"/admin/plays/#{@play.id}/export"}
            formats={
              if Playcode.Catalogue.Play.has_text?(@play),
                do: ~w(tei html pdf epub),
                else: ~w(tei)
            }
            target="_blank"
          />
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

      <.state_band play={@play} live={@play_live} />

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
                <PlayText.inline_content text={division.title || PlayLabels.division_name(division)} />
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
            :if={@play.relationship_type || @play.parent_play || @derived != []}
            id="work-relationship"
            title={gettext("Work Relationship")}
          >
            <div :if={@play.relationship_type || @play.parent_play} class="space-y-3">
              <p>
                <span :if={@play.relationship_type} class="badge badge-outline badge-sm mr-1">
                  {PlayLabels.relationship_type_label(@play.relationship_type)}
                </span>
                {into_language(@play)}
                <span :if={@play.parent_play || @play.original_title}>{gettext("of")}</span>
                <span :if={!@play.parent_play && @play.original_title} class="text-base-content/70">
                  {@play.original_title} ({gettext("not linked")})
                </span>
              </p>
              <div :if={@play.parent_play} class="rounded-box bg-base-200 px-3 py-2">
                <.link
                  navigate={~p"/admin/plays/#{@play.parent_play.id}"}
                  class="link link-primary font-medium"
                >
                  {@play.parent_play.title}
                </.link>
                <span class="font-mono text-xs text-base-content/70">
                  {Play.short_code(@play.parent_play.code)}
                </span>
                <p class="text-xs text-base-content/70">{original_line(@play.parent_play)}</p>
              </div>
              <details :if={@siblings != []}>
                <summary class="cursor-pointer text-sm font-semibold text-primary">
                  {gettext("The rest of its family (%{count})", count: length(@siblings))}
                </summary>
                <.family plays={@siblings} />
              </details>
            </div>
            <div :if={@derived != []} class={(@play.relationship_type || @play.parent_play) && "mt-4"}>
              <p>
                {ngettext(
                  "Original of %{count} play: %{kinds}.",
                  "Original of %{count} plays: %{kinds}.",
                  length(@derived),
                  kinds: kind_counts(@derived)
                )}
              </p>
              <details open class="mt-2">
                <summary class="cursor-pointer text-sm font-semibold text-primary">
                  {gettext("Show them")}
                </summary>
                <.family plays={@derived} />
              </details>
            </div>
          </.card>

          <.card :if={@play.revisions != []} title={gettext("Revisions")}>
            <ul id="revisions" class="divide-y divide-base-300">
              <li :for={change <- @play.revisions} class="py-1.5 text-sm">{revision(change)}</li>
            </ul>
          </.card>

          <.card title={gettext("Statistics")}>
            <:action>
              <.link
                :if={@statistic}
                navigate={~p"/admin/plays/#{@play.id}/statistics"}
                class="link link-primary"
              >
                {gettext("See all")}
              </.link>
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
          </.card>

          <.card :if={!@play.is_complete} title={gettext("Replace the text from Word")} dashed>
            <p class="mb-3 text-sm text-base-content/80">
              {gettext(
                "Paste the premarked text or drop its .docx, and see the play before importing."
              )}
            </p>
            <.link
              navigate={~p"/admin/plays/#{@play.id}/premarked"}
              class="btn btn-outline btn-primary btn-sm"
            >
              {gettext("Premarked text")}
            </.link>
          </.card>
        </div>
      </div>

      <.card title={gettext("Archive")} dashed>
        <p class="mb-3 text-sm text-base-content/80">
          {gettext("An archived play is hidden from the site. It can be restored.")}
        </p>
        <button
          phx-click="archive"
          data-confirm={
            gettext("Archive «%{title}»? It is hidden from the site and can be restored.",
              title: @play.title
            )
          }
          class="btn btn-outline btn-error btn-sm"
        >
          {gettext("Archive play")}
        </button>
      </.card>
    </.page>
    """
  end
end
