defmodule PlaycodeWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PlaycodeWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders breadcrumb navigation. Public pages only — the admin shell uses the
  sidebar and the play context bar instead.

  Each item is a map with `:label` and optional `:to` (path for link).
  The last item is rendered as plain text (current page).

  ## Examples

      <.breadcrumbs items={[%{label: "Catalogue", to: "/plays"}, %{label: "La Virginie"}]} />
  """
  attr :items, :list, required: true, doc: "list of %{label, to} maps"

  def breadcrumbs(assigns) do
    ~H"""
    <nav :if={@items != []} aria-label="Breadcrumb" class="text-sm breadcrumbs py-0">
      <ul>
        <li :for={{item, idx} <- Enum.with_index(@items)}>
          <.link
            :if={Map.get(item, :to) && idx < length(@items) - 1}
            navigate={item.to}
            class="hover:text-primary"
          >
            {item.label}
          </.link>
          <span :if={!Map.get(item, :to) || idx == length(@items) - 1} class="text-base-content/70">
            {item.label}
          </span>
        </li>
      </ul>
    </nav>
    """
  end

  @doc """
  Renders a play context bar for admin play pages.

  Shows the play title, code, author and quick-nav tabs to jump between
  different views of the same play.

  ## Examples

      <.play_context_bar play={@play} active_tab={:content} />
  """
  attr :play, :map, required: true, doc: "the play struct"

  attr :active_tab, :atom,
    default: nil,
    doc:
      "which tab is active (:overview, :metadata, :editors, :sources, :places, :content, :public)"

  def play_context_bar(assigns) do
    ~H"""
    <div class="border-b border-base-300 bg-base-100/80 backdrop-blur-sm">
      <div class="mx-auto max-w-7xl px-4 flex items-center justify-between gap-4 py-2">
        <.link
          navigate={~p"/admin/plays"}
          class="btn btn-ghost btn-sm btn-square flex-shrink-0 text-base-content/70 hover:text-base-content"
          aria-label={gettext("Back to plays")}
          title={gettext("Back to plays")}
        >
          <.icon name="hero-arrow-left-mini" class="size-5" />
        </.link>
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-semibold text-base-content truncate">{@play.title}</h2>
          <p class="text-xs text-base-content/60 truncate">
            {if @play.author_name, do: "#{@play.author_name} — "}{@play.code}
          </p>
        </div>
        <nav class="flex gap-1 flex-shrink-0">
          <.link
            navigate={~p"/admin/plays/#{@play.id}"}
            class={ctx_tab_class(@active_tab == :overview)}
          >
            {gettext("Overview")}
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/edit"}
            class={ctx_tab_class(@active_tab == :metadata)}
          >
            {gettext("Metadata")}
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/editors"}
            class={ctx_tab_class(@active_tab == :editors)}
          >
            {gettext("Editors")}
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/sources"}
            class={ctx_tab_class(@active_tab == :sources)}
          >
            {gettext("Sources")}
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/places"}
            class={ctx_tab_class(@active_tab == :places)}
          >
            {gettext("Places")}
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/content"}
            class={ctx_tab_class(@active_tab == :content)}
          >
            {gettext("Content")}
          </.link>
          <.link
            :if={
              @play.parent_play_id ||
                (Ecto.assoc_loaded?(@play.derived_plays) and @play.derived_plays != [])
            }
            navigate={~p"/admin/plays/#{@play.id}/compare"}
            class={ctx_tab_class(@active_tab == :compare)}
          >
            <.icon name="hero-arrows-right-left-micro" class="size-3.5" /> {gettext("Comparison")}
          </.link>
          <.link
            navigate={~p"/plays/#{@play.code}"}
            class={ctx_tab_class(@active_tab == :public)}
          >
            <.icon name="hero-eye-micro" class="size-3.5" /> {gettext("Public")}
          </.link>
        </nav>
      </div>
    </div>
    """
  end

  defp ctx_tab_class(true) do
    "inline-flex items-center gap-1 rounded-md px-2.5 py-1.5 text-xs font-medium bg-primary/10 text-primary"
  end

  defp ctx_tab_class(false) do
    "inline-flex items-center gap-1 rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/70 hover:bg-base-200 hover:text-base-content transition-colors"
  end

  @doc """
  Identity dropdown, locale toggle and theme toggle.

  Shared by both layouts — this markup existed twice and drifted apart.
  """
  attr :current_user, :map, default: nil
  attr :locale, :string, default: "es"

  def user_menu(assigns) do
    ~H"""
    <div class="flex-none flex items-center gap-2">
      <.locale_toggle locale={@locale} />
      <.theme_toggle />
      <div :if={@current_user} class="dropdown dropdown-end">
        <label tabindex="0" class="btn btn-ghost btn-xs gap-1">
          <.icon name="hero-user-circle-micro" class="size-4" />
          <span class="max-w-[8rem] truncate text-xs">{@current_user.email}</span>
          <.icon name="hero-chevron-down-micro" class="size-3" />
        </label>
        <ul
          tabindex="0"
          class="dropdown-content z-[1] menu p-1 shadow-lg bg-base-100 rounded-box w-48 border border-base-300"
        >
          <li><.link navigate={~p"/users/settings"}>{gettext("Settings")}</.link></li>
          <li><.link href={~p"/users/log-out"} method="delete">{gettext("Log out")}</.link></li>
        </ul>
      </div>
      <.link :if={!@current_user} navigate={~p"/users/log-in"} class="btn btn-ghost btn-xs">
        {gettext("Log in")}
      </.link>
    </div>
    """
  end

  @doc """
  Admin sidebar.

  Entries are filtered through `Playcode.Authz.can?/3`, the same predicate that
  guards the routes — so the menu cannot offer a page the user will be bounced
  from, and cannot hide one they are entitled to.
  """
  attr :current_user, :map, default: nil
  attr :current_path, :string, default: ""

  def admin_sidebar(assigns) do
    assigns = assign(assigns, :groups, sidebar_groups(assigns.current_user))

    ~H"""
    <aside class="w-56 shrink-0 border-r border-base-300 bg-base-200 min-h-full">
      <nav class="p-3 space-y-4">
        <div :for={{label, items} <- @groups}>
          <p class="px-2 pb-1 text-[0.65rem] font-semibold uppercase tracking-wider text-base-content/40">
            {label}
          </p>
          <ul class="menu menu-sm gap-0.5 p-0">
            <li :for={item <- items}>
              <.link
                navigate={item.to}
                class={if sidebar_active?(@current_path, item.to, @groups), do: "active", else: ""}
                aria-current={if sidebar_active?(@current_path, item.to, @groups), do: "page"}
              >
                <.icon name={item.icon} class="size-4" />
                {item.label}
              </.link>
            </li>
          </ul>
        </div>

        <div class="border-t border-base-300 pt-3">
          <ul class="menu menu-sm p-0">
            <li>
              <.link navigate={~p"/plays"}>
                <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" />
                {gettext("View public site")}
              </.link>
            </li>
          </ul>
        </div>
      </nav>
    </aside>
    """
  end

  defp sidebar_groups(user) do
    [
      {gettext("Content"),
       [
         %{
           label: gettext("Plays"),
           to: "/admin/plays",
           icon: "hero-book-open-micro",
           action: :manage_plays
         },
         %{
           label: gettext("Import"),
           to: "/admin/plays/import",
           icon: "hero-arrow-down-tray-micro",
           action: :import_tei
         },
         %{
           label: gettext("Places"),
           to: "/admin/places",
           icon: "hero-map-pin-micro",
           action: :manage_places
         },
         %{
           label: gettext("FileMaker"),
           to: "/admin/filemaker",
           icon: "hero-circle-stack-micro",
           action: :import_filemaker
         }
       ]},
      {gettext("Site"),
       [
         %{
           label: gettext("Export"),
           to: "/admin/export",
           icon: "hero-globe-alt-micro",
           action: :deploy_site
         },
         %{
           label: gettext("Activity"),
           to: "/admin/activity-log",
           icon: "hero-clock-micro",
           action: :view_activity_log
         }
       ]},
      {gettext("System"),
       [
         %{
           label: gettext("Users"),
           to: "/admin/users",
           icon: "hero-users-micro",
           action: :manage_users
         },
         %{
           label: gettext("Dashboard"),
           to: "/admin/dashboard",
           icon: "hero-chart-bar-micro",
           action: :view_dashboard
         }
       ]}
    ]
    |> Enum.map(fn {label, items} ->
      {label, Enum.filter(items, &Playcode.Authz.can?(user, &1.action))}
    end)
    |> Enum.reject(fn {_label, items} -> items == [] end)
  end

  # /admin/plays/import starts with /admin/plays, so the longest matching
  # entry wins — otherwise both light up on the import page.
  defp sidebar_active?(current_path, to, groups) do
    longest =
      groups
      |> Enum.flat_map(fn {_label, items} -> items end)
      |> Enum.map(& &1.to)
      |> Enum.filter(&String.starts_with?(current_path, &1))
      |> Enum.max_by(&String.length/1, fn -> nil end)

    longest == to
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <button
      class="btn btn-ghost btn-circle btn-sm swap swap-rotate"
      phx-click={JS.dispatch("phx:toggle-theme")}
      aria-label="Toggle theme"
    >
      <.icon name="hero-sun-micro" class="size-5 [[data-theme=dark]_&]:hidden" />
      <.icon name="hero-moon-micro" class="size-5 hidden [[data-theme=dark]_&]:block" />
    </button>
    """
  end

  @doc """
  Language toggle component (ES/EN).
  """
  attr :locale, :string, default: "es"

  def locale_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <form
        :if={@locale != "es"}
        action="/locale"
        method="post"
        class="inline"
        onsubmit="this.querySelector('[name=return_to]').value=window.location.pathname+window.location.search"
      >
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="locale" value="es" />
        <input type="hidden" name="return_to" value="" />
        <button type="submit" class="btn btn-ghost btn-xs font-bold">ES</button>
      </form>
      <span :if={@locale == "es"} class="btn btn-ghost btn-xs font-bold btn-active">ES</span>

      <form
        :if={@locale != "en"}
        action="/locale"
        method="post"
        class="inline"
        onsubmit="this.querySelector('[name=return_to]').value=window.location.pathname+window.location.search"
      >
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="locale" value="en" />
        <input type="hidden" name="return_to" value="" />
        <button type="submit" class="btn btn-ghost btn-xs font-bold">EN</button>
      </form>
      <span :if={@locale == "en"} class="btn btn-ghost btn-xs font-bold btn-active">EN</span>
    </div>
    """
  end
end
