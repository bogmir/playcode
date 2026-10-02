defmodule PlaycodeWeb.Admin.PlayFormLive do
  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.ActivityLog
  alias PlaycodeWeb.PlayLabels

  @al_project_description "El proyecto Artelope supone la creación de un banco de datos, argumentos y ediciones para un corpus fundamental del patrimonio literario español: el teatro de Lope de Vega y, extendido, en los últimos años, a Guillén de Castro."

  @emothe_project_description "La Colección de Textos Clásicos Europeos (CTCE) supone la creación de una base de datos de Teatro canónico clásico europeo en diferentes idiomas, versiones y refundiciones, todas ellas hipervinculadas."

  @default_editorial_declaration "Las presentes ediciones digitales están basadas, en su mayor parte, en ediciones científicas de reconocido prestigio y se ha tratado, en la mayoría de ocasiones, de respetar sus criterios de edición. Solo en casos muy puntuales el editor digital ha introducido leves cambios de los que da cumplida cuenta en el apartado de \u201cNotas\u201d."

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    play = %Play{}

    initial_params =
      %{"code" => Catalogue.next_play_code()}
      |> maybe_derive_emothe_id()
      |> maybe_apply_corpus_defaults()

    socket
    |> assign(:page_title, gettext("New Play"))
    |> assign(:play, play)
    |> assign(:form, to_form(Catalogue.change_play_form(play, initial_params)))
    |> assign(:parent_play_id, nil)
    |> assign(:parent_play_label, "")
    |> assign(:parent_play_search, "")
    |> assign(:parent_play_suggestions, [])
    |> assign(:attribution_mode, :select)
    |> assign(:play_context, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    play = Catalogue.get_play!(id)
    apply_edit_action(socket, play)
  end

  defp apply_edit_action(socket, play) do
    parent_label =
      if play.parent_play_id do
        parent = Catalogue.get_play!(play.parent_play_id)
        "#{parent.title} (#{parent.code})"
      else
        ""
      end

    attribution_mode =
      if play.author_attribution && !known_attribution?(play.author_attribution),
        do: :custom,
        else: :select

    socket
    |> assign(:page_title, "#{gettext("Edit")}: #{play.title}")
    |> assign(:play, play)
    |> assign(:form, to_form(Catalogue.change_play_form(play)))
    |> assign(:parent_play_id, play.parent_play_id)
    |> assign(:parent_play_label, parent_label)
    |> assign(:parent_play_search, "")
    |> assign(:parent_play_suggestions, [])
    |> assign(:attribution_mode, attribution_mode)
    |> assign(:play_context, %{play: play, active_tab: :metadata})
  end

  @impl true
  def handle_event("validate", %{"play" => play_params}, socket) do
    play_params =
      if socket.assigns.live_action == :new,
        do: maybe_apply_corpus_defaults(play_params),
        else: play_params

    # Auto-derive EMOTHE ID from code
    play_params = maybe_derive_emothe_id(play_params)

    # Handle attribution "Other..." selection
    {play_params, socket} =
      if play_params["author_attribution"] == "__other__" do
        {Map.put(play_params, "author_attribution", ""),
         assign(socket, :attribution_mode, :custom)}
      else
        {play_params, socket}
      end

    changeset = Catalogue.change_play_form(socket.assigns.play, play_params)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("save", %{"play" => play_params}, socket) do
    save_play(socket, socket.assigns.live_action, play_params)
  end

  def handle_event("suggest_parent", params, socket) do
    search = params["parent_play_search"] || ""

    suggestions =
      if String.trim(search) == "" do
        []
      else
        Catalogue.list_plays(search: search)
        |> Enum.reject(&(&1.id == socket.assigns.play.id))
        |> Enum.take(8)
      end

    {:noreply, assign(socket, parent_play_search: search, parent_play_suggestions: suggestions)}
  end

  def handle_event("pick_parent", %{"id" => id, "label" => label}, socket) do
    {:noreply,
     socket
     |> assign(:parent_play_id, id)
     |> assign(:parent_play_label, label)
     |> assign(:parent_play_search, "")
     |> assign(:parent_play_suggestions, [])}
  end

  def handle_event("clear_parent", _, socket) do
    {:noreply,
     socket
     |> assign(:parent_play_id, nil)
     |> assign(:parent_play_label, "")
     |> assign(:parent_play_search, "")
     |> assign(:parent_play_suggestions, [])}
  end

  def handle_event("copy_field", %{"source" => source, "target" => target}, socket) do
    form_data = socket.assigns.form.source.changes
    schema_data = socket.assigns.form.source.data

    source_atom = String.to_existing_atom(source)
    value = Map.get(form_data, source_atom) || Map.get(schema_data, source_atom) || ""

    # Update the form with the copied value
    current_params = form_params_from_changeset(socket.assigns.form.source)
    updated_params = Map.put(current_params, target, value)

    changeset = Catalogue.change_play_form(socket.assigns.play, updated_params)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate)))}
  end

  def handle_event("set_attribution_mode", %{"mode" => "custom"}, socket) do
    {:noreply, assign(socket, :attribution_mode, :custom)}
  end

  def handle_event("set_attribution_mode", %{"mode" => "select"}, socket) do
    {:noreply, assign(socket, :attribution_mode, :select)}
  end

  defp maybe_derive_emothe_id(params) do
    code = params["code"] || ""

    case Regex.run(~r/^(?:EMOTHE|CTCE)(\d+)/i, code) do
      [_, numeric_id] -> Map.put(params, "emothe_id", numeric_id)
      _ -> params
    end
  end

  defp emothe_id_derived?(form) do
    code = form_field_value(form, :code)
    Regex.match?(~r/^(?:EMOTHE|CTCE)\d+/i, code || "")
  end

  defp form_field_value(form, field) do
    case form[field] do
      %{value: val} -> val
      _ -> nil
    end
  end

  defp form_params_from_changeset(changeset) do
    data = changeset.data
    changes = changeset.changes

    Play.__schema__(:fields)
    |> Enum.reduce(%{}, fn field, acc ->
      val = Map.get(changes, field, Map.get(data, field))
      if val, do: Map.put(acc, Atom.to_string(field), val), else: acc
    end)
  end

  @attribution_options ~w(fiable dudosa atribuida anónima apócrifa)

  defp known_attribution?(value) do
    value in @attribution_options
  end

  defp attribution_options do
    [
      {"—", ""},
      {gettext("Fiable (reliable)"), "fiable"},
      {gettext("Dudosa (doubtful)"), "dudosa"},
      {gettext("Atribuida (attributed)"), "atribuida"},
      {gettext("Anónima (anonymous)"), "anónima"},
      {gettext("Apócrifa (apocryphal)"), "apócrifa"},
      {gettext("Other..."), "__other__"}
    ]
  end

  defp maybe_apply_corpus_defaults(params) do
    code = params["code"] || ""

    corpus_project =
      cond do
        String.starts_with?(code, "AL") -> @al_project_description
        String.starts_with?(code, "EMOTHE") -> @emothe_project_description
        true -> nil
      end

    if corpus_project do
      params
      |> fill_if_blank("project_description", corpus_project)
      |> fill_if_blank("editorial_declaration", @default_editorial_declaration)
    else
      params
    end
  end

  defp fill_if_blank(params, key, value) do
    if String.trim(params[key] || "") == "",
      do: Map.put(params, key, value),
      else: params
  end

  defp save_play(socket, :new, play_params) do
    case Catalogue.create_play_from_form(play_params) do
      {:ok, play} ->
        ActivityLog.log!(%{
          user_id: socket.assigns.current_user.id,
          play_id: play.id,
          action: "create",
          resource_type: "play",
          resource_id: play.id,
          metadata: %{title: play.title, code: play.code}
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Play created successfully."))
         |> push_navigate(to: ~p"/admin/plays/#{play.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_play(socket, :edit, play_params) do
    case Catalogue.update_play_from_form(socket.assigns.play, play_params) do
      {:ok, play} ->
        ActivityLog.log!(%{
          user_id: socket.assigns.current_user.id,
          play_id: play.id,
          action: "update",
          resource_type: "play",
          resource_id: play.id,
          metadata: %{title: play.title, code: play.code}
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Play updated successfully."))
         |> push_navigate(to: ~p"/admin/plays/#{play.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp relationship_type_options do
    [
      {gettext("— (Original / standalone)"), ""},
      {gettext("Translation"), "traduccion"},
      {gettext("Adaptation"), "adaptacion"},
      {gettext("Reworking"), "refundicion"}
    ]
  end

  defp language_options do
    [
      {gettext("Spanish"), "es"},
      {gettext("English"), "en"},
      {gettext("Italian"), "it"},
      {gettext("Catalan"), "ca"},
      {gettext("French"), "fr"},
      {gettext("Portuguese"), "pt"}
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">{@page_title}</h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Update bibliographic and editorial metadata for this play.")}
        </p>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".DirtyForm">
        export default {
          mounted() {
            this.dirty = false

            this.el.addEventListener("input", () => { this.dirty = true })
            this.el.addEventListener("submit", () => { this.dirty = false })

            this.navHandler = (e) => {
              if (!this.dirty) return
              const link = e.target.closest("a[data-phx-link]")
              if (!link) return
              if (!window.confirm("You have unsaved changes. Discard them?")) {
                e.preventDefault()
                e.stopPropagation()
              }
            }
            document.addEventListener("click", this.navHandler, true)

            this.beforeUnload = (e) => {
              if (this.dirty) { e.preventDefault(); e.returnValue = "" }
            }
            window.addEventListener("beforeunload", this.beforeUnload)
          },
          destroyed() {
            document.removeEventListener("click", this.navHandler, true)
            window.removeEventListener("beforeunload", this.beforeUnload)
          }
        }
      </script>

      <.form
        for={@form}
        id="play-form"
        phx-change="validate"
        phx-submit="save"
        phx-hook=".DirtyForm"
        class="space-y-6 rounded-box border border-base-300 bg-base-100 p-5 shadow-sm"
      >
        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Title")} *</span>
            </label>
            <.input field={@form[:title]} type="text" required />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">
                {gettext("Original Title")}
                <button
                  type="button"
                  phx-click="copy_field"
                  phx-value-source="title"
                  phx-value-target="original_title"
                  class="btn btn-ghost btn-xs ml-1"
                  title={gettext("Copy from Title")}
                >
                  <.icon name="hero-clipboard-document-mini" class="size-3" />
                </button>
              </span>
            </label>
            <.input
              field={@form[:original_title]}
              type="text"
              placeholder={gettext("Title in original language")}
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">
                {gettext("Title (sort)")}
                <button
                  type="button"
                  phx-click="copy_field"
                  phx-value-source="title"
                  phx-value-target="title_sort"
                  class="btn btn-ghost btn-xs ml-1"
                  title={gettext("Copy from Title")}
                >
                  <.icon name="hero-clipboard-document-mini" class="size-3" />
                </button>
              </span>
            </label>
            <.input
              field={@form[:title_sort]}
              type="text"
              placeholder={gettext("Alphabetical sorting form")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">
                {gettext("Edition Title")}
                <button
                  type="button"
                  phx-click="copy_field"
                  phx-value-source="title"
                  phx-value-target="edition_title"
                  class="btn btn-ghost btn-xs ml-1"
                  title={gettext("Copy from Title")}
                >
                  <.icon name="hero-clipboard-document-mini" class="size-3" />
                </button>
              </span>
            </label>
            <.input
              field={@form[:edition_title]}
              type="text"
              placeholder={gettext("Full editorial citation")}
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Code")} *</span>
            </label>
            <.input field={@form[:code]} type="text" required placeholder={gettext("e.g. AL0569")} />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("EMOTHE ID")}</span>
              <span :if={emothe_id_derived?(@form)} class="text-xs text-base-content/50 ml-1">
                {gettext("(auto)")}
              </span>
            </label>
            <.input
              field={@form[:emothe_id]}
              type="text"
              placeholder={gettext("e.g. 0703")}
              readonly={emothe_id_derived?(@form)}
            />
          </div>
        </div>

        <div class="space-y-3 rounded-box border border-base-300 bg-base-50 p-4">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Work Relationship")}
          </h3>
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Relationship Type")}</span>
              </label>
              <.input
                field={@form[:relationship_type]}
                type="select"
                options={relationship_type_options()}
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Original Work")}</span>
              </label>
              <%!-- Autocomplete combobox for parent play --%>
              <div class="relative">
                <%!-- Selected state --%>
                <div
                  :if={@parent_play_id}
                  class="input input-bordered flex items-center justify-between gap-2 h-auto min-h-[2.5rem] py-1.5"
                >
                  <span class="text-sm truncate">{@parent_play_label}</span>
                  <button
                    type="button"
                    phx-click="clear_parent"
                    class="btn btn-ghost btn-xs btn-circle shrink-0"
                    title={gettext("Clear")}
                  >
                    <.icon name="hero-x-mark-mini" class="size-3.5" />
                  </button>
                </div>
                <%!-- Search state --%>
                <div :if={!@parent_play_id}>
                  <input
                    type="text"
                    name="parent_play_search"
                    value={@parent_play_search}
                    phx-change="suggest_parent"
                    phx-debounce="200"
                    placeholder={gettext("Search by title or code...")}
                    class="input input-bordered w-full"
                    autocomplete="off"
                  />
                  <%!-- Suggestions dropdown --%>
                  <ul
                    :if={@parent_play_suggestions != []}
                    class="absolute z-20 mt-1 w-full bg-base-100 border border-base-300 rounded-box shadow-lg max-h-64 overflow-y-auto"
                  >
                    <li :for={sugg <- @parent_play_suggestions}>
                      <button
                        type="button"
                        phx-click="pick_parent"
                        phx-value-id={sugg.id}
                        phx-value-label={sugg.title}
                        class="w-full text-left px-3 py-2 hover:bg-base-200 transition-colors"
                      >
                        <div class="text-sm font-medium text-base-content truncate">
                          {sugg.title}
                        </div>
                        <div class="text-xs text-base-content/50 truncate mt-0.5">
                          {sugg.code}
                        </div>
                      </button>
                    </li>
                  </ul>
                  <p
                    :if={@parent_play_search == ""}
                    class="mt-1 text-xs text-base-content/50"
                  >
                    {gettext("Type to search for a play")}
                  </p>
                  <p
                    :if={@parent_play_search != "" && @parent_play_suggestions == []}
                    class="mt-1 text-xs text-base-content/50"
                  >
                    {gettext("No plays found")}
                  </p>
                </div>
                <%!-- Hidden input carries the value through form submit / validate --%>
                <input
                  type="hidden"
                  name={@form[:parent_play_id].name}
                  value={@parent_play_id || ""}
                />
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Author Name")}</span>
            </label>
            <.input field={@form[:author_name]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">
                {gettext("Author (sort)")}
                <button
                  type="button"
                  phx-click="copy_field"
                  phx-value-source="author_name"
                  phx-value-target="author_sort"
                  class="btn btn-ghost btn-xs ml-1"
                  title={gettext("Copy from Author Name")}
                >
                  <.icon name="hero-clipboard-document-mini" class="size-3" />
                </button>
              </span>
            </label>
            <.input field={@form[:author_sort]} type="text" placeholder={gettext("Surname, Name")} />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Language")}</span>
            </label>
            <.input field={@form[:language]} type="select" options={language_options()} />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Attribution")}</span>
            </label>
            <div :if={@attribution_mode == :select}>
              <.input
                field={@form[:author_attribution]}
                type="select"
                options={attribution_options()}
              />
            </div>
            <div :if={@attribution_mode == :custom} class="flex items-center gap-2">
              <div class="flex-1">
                <.input
                  field={@form[:author_attribution]}
                  type="text"
                  placeholder={gettext("Custom attribution...")}
                />
              </div>
              <button
                type="button"
                phx-click="set_attribution_mode"
                phx-value-mode="select"
                class="btn btn-ghost btn-sm"
                title={gettext("Switch to predefined values")}
              >
                <.icon name="hero-list-bullet-mini" class="size-4" />
              </button>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-3">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Publication Place")}</span>
            </label>
            <.input field={@form[:pub_place]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Publication Date")}</span>
            </label>
            <.input
              field={@form[:publication_date]}
              type="text"
              placeholder="e.g. 2023 or 01-01-2023"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Publisher")}</span>
            </label>
            <.input field={@form[:publisher]} type="text" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Authority")}</span>
            </label>
            <.input
              field={@form[:authority]}
              type="text"
              placeholder={gettext("Institutional authority")}
            />
          </div>
        </div>

        <div>
          <label class="label">
            <span class="label-text font-medium">{gettext("Availability Note")}</span>
          </label>
          <.input
            field={@form[:availability_note]}
            type="textarea"
            placeholder={gettext("Usage terms and citation info")}
          />
        </div>

        <div class="flex gap-4">
          <div class="rounded-box bg-base-200 px-3 py-2">
            <label class="flex items-center gap-2 text-sm text-base-content/85">
              <.input field={@form[:is_complete]} type="checkbox" /> {gettext("Complete")}
            </label>
          </div>
        </div>

        <div class="space-y-3 rounded-box border border-base-300 bg-base-50 p-4">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Project & Editorial")}
          </h3>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Project Description")}</span>
            </label>
            <.input
              field={@form[:project_description]}
              type="textarea"
              placeholder={gettext("Description of the digitization project")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Editorial Declaration")}</span>
            </label>
            <.input
              field={@form[:editorial_declaration]}
              type="textarea"
              placeholder={gettext("Editorial methodology and approach")}
            />
          </div>
        </div>

        <div class="space-y-3 rounded-box border border-base-300 bg-base-50 p-4">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Research Metadata")}
          </h3>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Form")}</span>
            </label>
            <.input field={@form[:form]} type="select" options={PlayLabels.form_options(@play)} />
            <p class="mt-1 text-xs text-base-content/60">
              {gettext("Automatic follows the text: verse when it has any verse lines.")}
            </p>
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Historical Time")}</span>
            </label>
            <.input
              field={@form[:historical_time]}
              type="select"
              options={PlayLabels.historical_time_options()}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Historical Time Note")}</span>
            </label>
            <.input
              field={@form[:historical_time_note]}
              type="textarea"
              placeholder={gettext("When the action is set, and the evidence for it")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Composition Date")}</span>
            </label>
            <div class="flex items-center gap-2">
              <.input
                field={@form[:composition_date_from]}
                type="number"
                placeholder={gettext("From")}
              />
              <span class="text-base-content/50">–</span>
              <.input
                field={@form[:composition_date_to]}
                type="number"
                placeholder={gettext("To")}
              />
            </div>
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Composition Date Note")}</span>
            </label>
            <.input
              field={@form[:composition_date_note]}
              type="textarea"
              placeholder={gettext("Competing datings, and the evidence for each")}
            />
          </div>
        </div>

        <div class="space-y-3 rounded-box border border-base-300 bg-base-50 p-4">
          <h3 class="text-sm font-semibold uppercase tracking-wide text-base-content/60">
            {gettext("Funding & Licence")}
          </h3>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Sponsor")}</span>
            </label>
            <.input
              field={@form[:sponsor]}
              type="text"
              placeholder={gettext("Sponsoring organization")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Funder")}</span>
            </label>
            <.input
              field={@form[:funder]}
              type="textarea"
              placeholder={gettext("Funding organization(s) and grant references")}
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Licence URL")}</span>
            </label>
            <.input
              field={@form[:licence_url]}
              type="text"
              placeholder="https://creativecommons.org/licenses/..."
            />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Licence Text")}</span>
            </label>
            <.input
              field={@form[:licence_text]}
              type="text"
              placeholder={gettext("e.g. CC BY-NC-ND 4.0")}
            />
          </div>
        </div>

        <div class="flex flex-wrap gap-2 border-t border-base-300 pt-4">
          <button type="submit" class="btn btn-primary">
            {gettext("Save Play")}
          </button>
          <.link navigate={~p"/admin/plays"} class="btn btn-ghost">
            {gettext("Cancel")}
          </.link>
        </div>
      </.form>
    </div>
    """
  end
end
