defmodule Playcode.Export.StaticSite.Fingerprint do
  @moduledoc """
  Everything the static site's pages are built with except the play data, as one hash.
  `build.json` records the one a site was built with; when the current one differs, any
  page may be out of date, and Generate rebuilds every play.

  It covers the code (`module_info(:md5)` of `modules/0`), the files under
  `priv/static_site`, the versions of the libraries that render and encode the pages,
  and the `:version` option. Not `build_date`: a page's footer says when that page was
  written. Not `base_url`: nothing reads it. The play data is `plays.content_version`'s.

  `test/playcode/export/static_site/fingerprint_test.exs` fails when the export starts
  calling a module of this app that is neither listed here nor data access.
  """

  @prefix "Elixir.Playcode.Export.StaticSite"

  # The modules outside StaticSite whose code shapes a page.
  @modules [
    Playcode.Export.TeiXml,
    Playcode.Statistics,
    Playcode.Statistics.Metrics,
    Playcode.Catalogue.Play,
    Playcode.PlayContent.InlineMarkup,
    Playcode.PlayContent.Element,
    Playcode.Places,
    PlaycodeWeb.PlayLabels,
    PlaycodeWeb.Gettext
  ]

  @libraries [:phoenix_live_view, :phoenix_html, :jason, :xml_builder]

  @doc """
  Every `Playcode.Export.StaticSite*` module and the modules listed above. Read from the
  application's module list, not the loaded modules: in dev a module loads on first use,
  so a list of loaded ones would differ before and after the first build.
  """
  def modules do
    exported =
      Enum.filter(
        Application.spec(:playcode, :modules),
        &String.starts_with?(Atom.to_string(&1), @prefix)
      )

    Enum.sort(exported ++ @modules)
  end

  @doc "A hex SHA-256 of what the pages are built with. Reads only `opts[:version]`."
  def current(opts) do
    code = Enum.map(modules(), &{&1, &1.module_info(:md5)})
    libraries = Enum.map(@libraries, &{&1, Application.spec(&1, :vsn)})

    {code, assets(), libraries, opts[:version]}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # Each file under priv/static_site, by its path there, with its contents.
  defp assets do
    dir = Application.app_dir(:playcode, "priv/static_site")

    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map(&{Path.relative_to(&1, dir), File.read!(&1)})
  end
end
