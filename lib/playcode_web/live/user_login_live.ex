defmodule PlaycodeWeb.UserLoginLive do
  @moduledoc false

  use PlaycodeWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8 md:py-16">
      <div class="grid overflow-hidden rounded-box border border-base-300 md:grid-cols-[1.1fr_1fr]">
        <section class="flex flex-col justify-between gap-10 border-b border-base-300 bg-base-200 p-8 md:border-r md:border-b-0 md:p-10">
          <div>
            <img src={~p"/images/logo.svg"} width="56" height="56" alt="" />
            <p class="mt-4 font-serif text-3xl font-semibold">Playcode</p>
            <p class="mt-1 max-w-xs text-base-content/70">
              {gettext("Where early modern European plays are catalogued, edited and published.")}
            </p>
            <p class="mt-4 text-xs font-semibold uppercase tracking-wider text-primary">
              EMOTHE · ARTELOPE
            </p>
          </div>
          <figure class="max-md:hidden">
            <blockquote lang="es" class="font-serif text-xl italic leading-relaxed">
              <p>¿Qué es la vida? Un frenesí.</p>
              <p>¿Qué es la vida? Una ilusión,</p>
              <p>una sombra, una ficción…</p>
            </blockquote>
            <figcaption class="mt-3 text-sm text-base-content/70">
              Calderón, <cite>La vida es sueño</cite>, vv. 2182–2184
            </figcaption>
          </figure>
        </section>

        <div class="flex items-center p-8 md:p-10">
          <div class="w-full">
            <h1 class="font-serif text-2xl font-semibold">{gettext("Log in")}</h1>
            <p class="mt-1 text-base-content/70">
              {gettext("With the email your invitation came to.")}
            </p>

            <.form
              for={@form}
              id="login_form"
              action={~p"/users/log-in"}
              phx-update="ignore"
              class="mt-6"
            >
              <.input field={@form[:email]} type="email" label={gettext("Email")} required />
              <.input
                field={@form[:password]}
                type="password"
                label={gettext("Password")}
                required
              />
              <div class="mt-2 mb-5 flex flex-wrap items-center justify-between gap-2 [&>.fieldset]:mb-0">
                <.input
                  field={@form[:remember_me]}
                  type="checkbox"
                  label={gettext("Keep me logged in")}
                />
                <.link
                  href={~p"/users/reset-password"}
                  class="link link-primary text-sm font-semibold"
                >
                  {gettext("Forgot your password?")}
                </.link>
              </div>
              <.button phx-disable-with={gettext("Logging in...")} class="btn btn-primary w-full">
                {gettext("Log in")}
              </.button>
            </.form>

            <p class="mt-4 text-xs text-base-content/70">
              {gettext("Access is by invitation. Contact an administrator to request an account.")}
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
