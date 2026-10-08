defmodule PlaycodeWeb.LocaleController do
  @moduledoc false

  use PlaycodeWeb, :controller

  def update(conn, %{"locale" => locale} = params) when locale in ~w(es en) do
    conn
    |> put_session(:locale, locale)
    |> redirect(to: safe_return_to(params))
  end

  def update(conn, params) do
    conn
    |> redirect(to: safe_return_to(params))
  end

  # "//host" and "/\host" are protocol-relative URLs to another host, which
  # redirect/2 refuses with an ArgumentError (a 500), so they fall back to "/".
  defp safe_return_to(%{"return_to" => "/" <> rest = path}) do
    if String.starts_with?(rest, ["/", "\\"]), do: "/", else: path
  end

  defp safe_return_to(_), do: "/"
end
