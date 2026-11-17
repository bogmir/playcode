defmodule PlaycodeWeb.Plugs.RequireText do
  @moduledoc """
  A play without a text has no HTML, PDF or EPUB: the download is refused before anything
  is rendered or cached, and the reader goes back with the notice, to the play's preview
  (`:preview`) or its admin page (`:admin`), where the link was.
  """
  use PlaycodeWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2]

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play

  def init(back) when back in [:preview, :admin], do: back

  def call(%{params: %{"id" => id}} = conn, back) do
    play = Catalogue.get_play!(id)

    if Play.has_text?(play) do
      conn
    else
      conn
      |> put_flash(:info, PlaycodeWeb.PlayLabels.no_text_notice())
      |> redirect(to: back_to(back, play))
      |> halt()
    end
  end

  defp back_to(:preview, play), do: ~p"/plays/#{play.code}"
  defp back_to(:admin, play), do: ~p"/admin/plays/#{play.id}"
end
