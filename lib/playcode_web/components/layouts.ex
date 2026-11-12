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
    <nav :if={@items != []} aria-label={gettext("Breadcrumb")} class="text-sm breadcrumbs py-0">
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
        <label
          tabindex="0"
          role="button"
          aria-label={@current_user.email}
          class="btn btn-ghost btn-xs gap-1"
        >
          <.icon name="hero-user-circle-micro" class="size-4" />
          <span class="hidden sm:inline max-w-[8rem] truncate text-xs">
            {@current_user.email}
          </span>
          <.icon name="hero-chevron-down-micro" class="size-3" />
        </label>
        <ul
          tabindex="0"
          class="dropdown-content z-[1] menu p-1 shadow-lg bg-base-100 text-base-content rounded-box w-48 border border-base-300"
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
  Admin sidebar: the admin's sections, or on a play's pages (`play_context`) the play's own,
  grouped as the mockup groups them, each with its count from `play_counts`.

  Both are filtered through `Playcode.Authz.can?/3`, the same predicate that guards the
  routes, so the menu cannot offer a page the user will be bounced from, and cannot hide one
  they are entitled to.
  """
  attr :current_user, :map, default: nil
  attr :current_path, :string, default: ""
  attr :play_context, :map, default: nil
  attr :play_counts, :map, default: nil
  attr :play_deployed, :integer, default: nil, doc: "the version the last deploy published"

  def admin_sidebar(%{play_context: %{play: _}} = assigns) do
    assigns =
      assigns
      |> assign(:play, assigns.play_context.play)
      |> assign(:active, assigns.play_context.active_tab)
      |> assign(:counts, assigns.play_counts || %{})

    ~H"""
    <aside class="w-full border-b border-base-300 bg-base-200 lg:min-h-full lg:w-56 lg:border-r lg:border-b-0">
      <nav aria-label={gettext("Play sections")} class="p-3 text-sm">
        <.link navigate={~p"/admin/plays"} class="mb-3 block px-2 text-primary hover:underline">
          ← {gettext("All plays")}
        </.link>
        <p class="px-2 font-serif font-semibold leading-snug text-base-content">{@play.title}</p>
        <p class="mb-3 px-2 font-mono text-xs text-base-content/70 break-all">{@play.code}</p>
        <.section_link to={~p"/admin/plays/#{@play.id}"} current={@active == :overview}>
          {gettext("Overview")}
        </.section_link>
        <%= for {group, items} <- play_sections(@play, @current_user, @play_deployed) do %>
          <h2 class="mx-2 mt-4 mb-1 text-xs font-semibold uppercase tracking-wider text-base-content/70">
            {group}
          </h2>
          <.section_link
            :for={{tab, label, to, count_key} <- items}
            to={to}
            current={@active == tab}
            count={count_key && Map.get(@counts, count_key)}
          >
            {label}
          </.section_link>
        <% end %>
      </nav>
    </aside>
    """
  end

  def admin_sidebar(assigns) do
    assigns = assign(assigns, :groups, sidebar_groups(assigns.current_user))

    ~H"""
    <aside class="w-full border-b border-base-300 bg-base-200 lg:min-h-full lg:w-56 lg:border-r lg:border-b-0">
      <nav aria-label={gettext("Administration")} class="p-3 text-sm">
        <div :for={{label, items} <- @groups} class="mb-4">
          <h2 class="mx-2 mb-1 text-xs font-semibold uppercase tracking-wider text-base-content/70">
            {label}
          </h2>
          <.section_link
            :for={item <- items}
            to={item.to}
            current={sidebar_active?(@current_path, item.to, @groups)}
          >
            <.icon name={item.icon} class="size-4" /> {item.label}
          </.section_link>
        </div>

        <div class="border-t border-base-300 pt-3">
          <.section_link to={~p"/plays"}>
            <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" />
            {gettext("View public site")}
          </.section_link>
        </div>
      </nav>
    </aside>
    """
  end

  attr :to, :string, required: true
  attr :current, :boolean, default: false
  attr :count, :integer, default: nil
  slot :inner_block, required: true

  # A link out of Playcode (the published site's page) opens in a tab of its own.
  defp section_link(assigns) do
    assigns = assign(assigns, :external, String.starts_with?(assigns.to, "http"))

    ~H"""
    <.link
      navigate={!@external && @to}
      href={@external && @to}
      target={@external && "_blank"}
      rel={@external && "noopener"}
      aria-current={@current && "page"}
      class={[
        "flex items-center justify-between gap-2 rounded-field px-2 py-1.5",
        if(@current,
          do: "bg-primary/10 font-semibold text-primary",
          else: "text-base-content/80 hover:bg-base-300/50 hover:text-base-content"
        )
      ]}
    >
      <span class="flex min-w-0 items-center gap-2">{render_slot(@inner_block)}</span>
      <.icon :if={@external} name="hero-arrow-top-right-on-square-micro" class="size-4" />
      <span :if={@count} class="tabular-nums text-base-content/70">{@count}</span>
    </.link>
    """
  end

  # The play's sections as the mockup groups them: {tab, label, path, count key}. Every one
  # is behind :view_admin but the preview, Playcode's public page, which shows a draft to
  # :view_drafts only; the play is passed for the per-play scoping `Authz` plans.
  defp play_sections(play, user, deployed) do
    related? =
      play.parent_play_id || (Ecto.assoc_loaded?(play.derived_plays) and play.derived_plays != [])

    [
      {gettext("Record"),
       [
         {:metadata, gettext("Metadata"), ~p"/admin/plays/#{play.id}/edit", nil},
         {:editors, gettext("Editors"), ~p"/admin/plays/#{play.id}/editors", :editors},
         {:sources, gettext("Sources"), ~p"/admin/plays/#{play.id}/sources", :sources}
       ]},
      {gettext("Tradition"),
       [
         {:witnesses, gettext("Witnesses"), ~p"/admin/plays/#{play.id}/witnesses", :witnesses},
         {:performances, gettext("Performances"), ~p"/admin/plays/#{play.id}/performances",
          :performances},
         {:bibliography, gettext("Bibliography"), ~p"/admin/plays/#{play.id}/bibliography",
          :bibliography},
         {:places, gettext("Places"), ~p"/admin/plays/#{play.id}/places", :places}
       ]},
      {gettext("Text"),
       [
         {:content, gettext("Content"), ~p"/admin/plays/#{play.id}/content", nil},
         {:notes, gettext("Notes"), ~p"/admin/plays/#{play.id}/notes", :notes}
       ]},
      {gettext("View"),
       Enum.reject(
         [
           related? &&
             {:compare, gettext("Comparison"), ~p"/admin/plays/#{play.id}/compare", nil},
           {:preview, gettext("Preview"), ~p"/plays/#{play.code}", nil},
           deployed && public_page(play)
         ],
         &(!&1)
       )}
    ]
    |> Enum.map(fn {group, items} ->
      {group, Enum.filter(items, &Playcode.Authz.can?(user, section_action(&1), play))}
    end)
    |> Enum.reject(fn {_group, items} -> items == [] end)
  end

  # The play's page on the published site, when the site's public address is set.
  defp public_page(play) do
    if url = Playcode.Export.StaticSite.public_page_url(play.code),
      do: {:public, gettext("Public page"), url, nil}
  end

  defp section_action({:preview, _label, _to, _count}), do: :view_drafts
  defp section_action(_section), do: :view_admin

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
      aria-label={gettext("Toggle theme")}
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
