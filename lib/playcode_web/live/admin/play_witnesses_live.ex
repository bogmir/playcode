defmodule PlaycodeWeb.Admin.PlayWitnessesLive do
  @moduledoc """
  /admin/plays/:id/witnesses: the manuscripts and early printings the play's text survives
  in (S3), in order, each previewed as the public pages print it. Spec:
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Witnesses
  alias Playcode.Witnesses.Witness
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Witnesses")}")
     |> assign(:play, play)
     |> assign(:witnesses, Witnesses.list_for_play(play.id))
     |> assign(editing: nil, form: nil)
     |> assign(:play_context, %{play: play, active_tab: :witnesses})}
  end

  @impl true
  def handle_event("new_witness", _, socket) do
    {:noreply, edit(socket, :new, %Witness{play_id: socket.assigns.play.id})}
  end

  def handle_event("edit_witness", %{"id" => id}, socket) do
    with_witness(socket, id, &edit(socket, &1, &1))
  end

  def handle_event("cancel_edit", _, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate_witness", %{"witness" => params}, socket) do
    changeset =
      socket |> editing_base() |> Witnesses.change_witness(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save_witness", %{"witness" => params}, socket) do
    {action, result} =
      case socket.assigns.editing do
        :new ->
          {"create", Witnesses.create_witness(Map.put(params, "play_id", socket.assigns.play.id))}

        witness ->
          {"update", Witnesses.update_witness(witness, params)}
      end

    case result do
      {:ok, witness} ->
        log(socket, action, witness)

        message =
          if action == "create", do: gettext("Witness added."), else: gettext("Witness updated.")

        {:noreply,
         socket |> reload() |> assign(editing: nil, form: nil) |> put_flash(:info, message)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("move_up", %{"id" => id}, socket), do: move(socket, id, :up)
  def handle_event("move_down", %{"id" => id}, socket), do: move(socket, id, :down)

  def handle_event("delete_witness", %{"id" => id}, socket) do
    with_witness(socket, id, fn witness ->
      {:ok, _} = Witnesses.delete_witness(witness)
      log(socket, "delete", witness)
      socket |> reload() |> put_flash(:info, gettext("Witness deleted."))
    end)
  end

  defp move(socket, id, direction) do
    with_witness(socket, id, fn witness ->
      :ok = Witnesses.move_witness(witness, direction)
      reload(socket)
    end)
  end

  defp edit(socket, editing, witness),
    do: assign(socket, editing: editing, form: to_form(Witnesses.change_witness(witness)))

  defp editing_base(%{assigns: %{editing: :new, play: play}}), do: %Witness{play_id: play.id}
  defp editing_base(%{assigns: %{editing: witness}}), do: witness

  # The witness the event named, or the list reloaded with a flash when it is not this
  # play's: see LiveHelpers.put_gone_flash/1.
  defp with_witness(socket, id, fun) do
    case Witnesses.get_witness(socket.assigns.play.id, id) do
      nil -> {:noreply, socket |> reload() |> LiveHelpers.put_gone_flash()}
      witness -> {:noreply, fun.(witness)}
    end
  end

  defp reload(socket),
    do: assign(socket, :witnesses, Witnesses.list_for_play(socket.assigns.play.id))

  defp log(socket, action, witness) do
    LiveHelpers.log_activity(socket, action, "play_witness", witness.id, %{
      siglum: witness.siglum,
      title: witness.title || witness.normalized_title
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Witnesses")}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("The manuscripts and early printings the text survives in.")}
          </p>
        </div>
        <button :if={@editing == nil} phx-click="new_witness" class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add witness")}
        </button>
      </div>

      <div :if={@form} class="mb-6 rounded-box border border-primary/30 bg-base-100 p-5 shadow-md">
        <h2 class="mb-4 text-sm font-semibold text-primary">
          {if @editing == :new, do: gettext("New witness"), else: gettext("Edit witness")}
        </h2>
        <.form for={@form} id="witness-form" phx-change="validate_witness" phx-submit="save_witness">
          <div class="grid grid-cols-1 gap-x-4 md:grid-cols-2">
            <.input field={@form[:siglum]} type="text" label={gettext("Siglum")} />
            <.input
              field={@form[:witness_type]}
              type="select"
              label={gettext("Type")}
              prompt={gettext("Not stated")}
              options={PlayLabels.witness_type_options()}
            />
            <.input field={@form[:title]} type="text" label={gettext("Title as printed")} />
            <.input field={@form[:normalized_title]} type="text" label={gettext("Normalised title")} />
            <.input field={@form[:attribution]} type="text" label={gettext("Attribution")} />
            <.input field={@form[:pub_place]} type="text" label={gettext("Place")} />
            <.input field={@form[:publisher]} type="text" label={gettext("Publisher")} />
            <.input field={@form[:date]} type="text" label={gettext("Date")} />
            <.input field={@form[:format]} type="text" label={gettext("Format")} />
            <.input field={@form[:shelfmark]} type="text" label={gettext("Shelfmark")} />
          </div>
          <.input field={@form[:note]} type="textarea" rows="3" label={gettext("Observation")} />
          <p class="mt-2 text-xs text-base-content/70">{gettext("As it will print")}</p>
          <p id="witness-preview" class="font-serif text-sm">
            {Witnesses.html(Ecto.Changeset.apply_changes(@form.source))}
          </p>
          <div class="mt-4 flex justify-end gap-2">
            <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
          </div>
        </.form>
      </div>

      <div :if={@witnesses == [] && @form == nil} class="py-12 text-center text-base-content/70">
        <.icon name="hero-book-open" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No witnesses yet.")}</p>
        <button phx-click="new_witness" class="btn btn-ghost btn-sm mt-3">
          {gettext("Add the first witness")}
        </button>
      </div>

      <ol class="space-y-3">
        <li
          :for={witness <- @witnesses}
          id={"witness-#{witness.id}"}
          class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 text-sm">
              <span :if={witness.siglum} class="badge badge-ghost badge-sm mr-1 font-mono">
                {witness.siglum}
              </span>
              <span :if={witness.witness_type} class="text-xs text-base-content/70">
                {PlayLabels.witness_type_label(witness.witness_type)}
              </span>
              <p class="mt-1 font-serif">{Witnesses.html(witness)}</p>
            </div>
            <div class="flex shrink-0 gap-1">
              <button
                phx-click="move_up"
                phx-value-id={witness.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Move up")}
              >
                <.icon name="hero-arrow-up-micro" class="size-3.5" />
              </button>
              <button
                phx-click="move_down"
                phx-value-id={witness.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Move down")}
              >
                <.icon name="hero-arrow-down-micro" class="size-3.5" />
              </button>
              <button
                phx-click="edit_witness"
                phx-value-id={witness.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Edit")}
              >
                <.icon name="hero-pencil-square-micro" class="size-3.5" />
              </button>
              <button
                phx-click="delete_witness"
                phx-value-id={witness.id}
                data-confirm={gettext("Delete this witness?")}
                class="btn btn-ghost btn-xs text-error"
                aria-label={gettext("Delete")}
              >
                <.icon name="hero-trash-micro" class="size-3.5" />
              </button>
            </div>
          </div>
        </li>
      </ol>
    </div>
    """
  end
end
