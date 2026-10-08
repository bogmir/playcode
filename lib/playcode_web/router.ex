defmodule PlaycodeWeb.Router do
  @moduledoc false

  use PlaycodeWeb, :router

  import PlaycodeWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PlaycodeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug PlaycodeWeb.Plugs.SetLocale
    plug PlaycodeWeb.Plugs.StoreLastPath
  end

  pipeline :demo_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PlaycodeWeb.Layouts, :demo_root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # pipe_through cannot pass options to a plug, so each named permission gets
  # its own pipeline. Every one of them asks Playcode.Authz.can?/3.
  pipeline :require_admin_area do
    plug :require_permission, :view_admin
  end

  pipeline :require_deploy do
    plug :require_permission, :deploy_site
  end

  # The built site's files, behind the deploy gate but without the page plugs: each
  # asset is its own request, and none of them is a page to remember. The locale is only for the refusal flash.
  pipeline :site_preview do
    plug :fetch_session
    plug :fetch_flash
    plug :fetch_current_user
    plug PlaycodeWeb.Plugs.SetLocale
    plug :require_permission, :deploy_site
  end

  pipeline :require_dashboard do
    plug :require_permission, :view_dashboard
  end

  # Public API
  scope "/api/v1", PlaycodeWeb.API do
    pipe_through :api

    get "/plays", PlayController, :index
    get "/plays/:code", PlayController, :show
    get "/plays/:code/characters", PlayController, :characters
    get "/plays/:code/text", PlayController, :text
    get "/plays/:code/statistics", PlayController, :statistics
  end

  # Public routes
  scope "/", PlaycodeWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/locale", LocaleController, :update

    # Public export endpoints
    get "/export/:id/tei", ExportController, :tei
    get "/export/:id/html", ExportController, :html
    get "/export/:id/pdf", ExportController, :pdf
    get "/export/:id/epub", ExportController, :epub

    # Public play catalogue and presentation
    live_session :public,
      layout: {PlaycodeWeb.Layouts, :app},
      on_mount: [PlaycodeWeb.SetLocaleHook, {PlaycodeWeb.UserAuth, :mount_current_user}] do
      live "/plays", PlayCatalogueLive, :index
      live "/plays/:code", PlayShowLive, :show
      live "/plays/:code/compare", PlayCompareLive, :compare
    end
  end

  ## Authentication routes

  scope "/", PlaycodeWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      layout: {PlaycodeWeb.Layouts, :app},
      on_mount: [
        PlaycodeWeb.SetLocaleHook,
        {PlaycodeWeb.UserAuth, :redirect_if_user_is_authenticated}
      ] do
      live "/users/log-in", UserLoginLive, :new
      live "/users/reset-password", UserForgotPasswordLive, :new
    end
  end

  # An emailed token — invitation or password reset — must work on a browser
  # that already holds a session: the token, not the current session, is the
  # authority over which account is being set up. The admin who sent an invite
  # often clicks the link themselves, and an unconfirmed account can log in
  # while every gate refuses it, so the reset link is that user's only way out
  # — and holding a session was exactly what swallowed it. Both pages and the
  # login POST they submit to therefore sit outside
  # :redirect_if_user_is_authenticated, and logging in renews the session, so
  # the old one is replaced rather than merged.
  scope "/", PlaycodeWeb do
    pipe_through [:browser]

    live_session :emailed_token,
      layout: {PlaycodeWeb.Layouts, :app},
      on_mount: [PlaycodeWeb.SetLocaleHook, {PlaycodeWeb.UserAuth, :mount_current_user}] do
      live "/users/accept-invite/:token", UserAcceptInviteLive, :edit
      live "/users/reset-password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log-in", UserSessionController, :create
  end

  scope "/", PlaycodeWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [PlaycodeWeb.SetLocaleHook, {PlaycodeWeb.UserAuth, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
    end
  end

  scope "/", PlaycodeWeb do
    pipe_through [:browser]

    delete "/users/log-out", UserSessionController, :delete
  end

  # Admin routes - requires the :view_admin permission
  scope "/admin", PlaycodeWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_admin_area]

    live_session :admin,
      layout: {PlaycodeWeb.Layouts, :admin},
      on_mount: [
        PlaycodeWeb.SetLocaleHook,
        PlaycodeWeb.CurrentPathHook,
        {PlaycodeWeb.UserAuth, {:ensure_can, :view_admin}}
      ] do
      live "/plays", PlayListLive, :index
      live "/plays/new", PlayFormLive, :new
      live "/plays/:id/edit", PlayFormLive, :edit
      live "/plays/import", ImportLive, :index
      live "/plays/:id", PlayDetailLive, :show
      live "/plays/:id/editors", PlayEditorsLive, :index
      live "/plays/:id/sources", PlaySourcesLive, :index
      live "/plays/:id/places", PlayPlacesLive, :index
      live "/plays/:id/bibliography", PlayBibliographyLive, :index
      live "/plays/:id/content", PlayContentEditorLive, :index
      live "/plays/:id/compare", PlayCompareLive, :compare
      live "/places", PlaceListLive, :index
      live "/users", UserListLive, :index
      live "/activity-log", ActivityLogLive, :index
      live "/export", ExportSiteLive, :index
      live "/filemaker", FilemakerSyncLive, :index
    end

    # Export endpoints
    get "/plays/compare/export/html", ExportController, :compare_html
    get "/plays/:id/export/tei", ExportController, :tei
    get "/plays/:id/export/html", ExportController, :html
    get "/plays/:id/export/pdf", ExportController, :pdf
    get "/plays/:id/export/epub", ExportController, :epub
  end

  # Site deployment download sits behind :deploy_site, not :view_admin
  scope "/admin", PlaycodeWeb.Admin do
    pipe_through [:browser, :require_authenticated_user, :require_deploy]

    get "/export/download-zip", ExportController, :download_zip
  end

  scope "/admin", PlaycodeWeb.Admin do
    pipe_through :site_preview

    get "/export/preview/*path", ExportController, :preview
  end

  # LiveDashboard, behind :view_dashboard (all environments)
  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user, :require_dashboard]

    live_dashboard "/dashboard", metrics: PlaycodeWeb.Telemetry
  end

  # Swoosh mailbox preview in development only
  if Application.compile_env(:playcode, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

    scope "/demo/ui", PlaycodeWeb do
      pipe_through :demo_browser

      get "/", DemoUIController, :index
      get "/public/catalogue", DemoUIController, :public_catalogue
      get "/public/play", DemoUIController, :public_play
      get "/admin/plays", DemoUIController, :admin_plays
      get "/admin/play", DemoUIController, :admin_play
      get "/admin/import", DemoUIController, :admin_import
    end
  end
end
