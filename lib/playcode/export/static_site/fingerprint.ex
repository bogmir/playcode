defmodule Playcode.Export.StaticSite.Fingerprint do
  @moduledoc """
  Everything the static site's pages are built with except the play data, as one hash.
  `build.json` records the one a site was built with; when the current one differs, any
  page may be out of date, and Generate rebuilds every play.

  It covers the code (`module_info(:md5)` of `modules/0`), the files under
  `priv/static_site`, the English translations, the versions of the libraries that render
  and encode the pages, and the `:version` option. Not `build_date`: a page's footer says
  when that page was written. The play data is `plays.content_version`'s.

  Not `PlaycodeWeb.Gettext`'s code: it is compiled from every locale's translations, so a
  Spanish edit in the admin pages changed it, and the site is in English. Its English
  translations are hashed as data instead; an untranslated message falls back to its
  msgid, which is in the code of the module that asks for it.

  `test/playcode/export/static_site/fingerprint_test.exs` fails when the export starts
  calling a module of this app that is neither listed here nor data access.
  """

  @prefix "Elixir.Playcode.Export.StaticSite"

  # The modules outside StaticSite whose code shapes a page.
  @modules [
    Playcode.Export.TeiXml,
    Playcode.Bibliography,
    Playcode.Bibliography.Citation,
    Playcode.Bibliography.Entry,
    Playcode.Statistics,
    Playcode.Statistics.Metrics,
    Playcode.Catalogue.Play,
    Playcode.PlayContent.InlineMarkup,
    Playcode.PlayContent.Element,
    Playcode.Places,
    Playcode.Places.Place,
    Playcode.Places.PlayPlace,
    PlaycodeWeb.PlayLabels
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

  @doc """
  A hex SHA-256 of what the pages are built with, for `opts[:version]`. `:gettext_dir`
  reads the translations from another directory than `priv/gettext`.
  """
  def current(opts) do
    code = Enum.map(modules(), &{&1, &1.module_info(:md5)})
    libraries = Enum.map(@libraries, &{&1, Application.spec(&1, :vsn)})
    gettext_dir = opts[:gettext_dir] || Application.app_dir(:playcode, "priv/gettext")

    {code, assets(), english(gettext_dir), libraries, opts[:version]}
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

  # The English translations that say something, by message: not the files, whose
  # source-line references move with every edit of the code.
  defp english(gettext_dir) do
    gettext_dir
    |> Path.join("en/LC_MESSAGES/*.po")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.flat_map(fn path ->
      for message <- Expo.PO.parse_file!(path).messages,
          translation = translation(message),
          translation != [],
          do: {Path.basename(path), Expo.Message.key(message), translation}
    end)
    |> Enum.sort()
  end

  defp translation(%Expo.Message.Singular{msgstr: msgstr}),
    do: msgstr |> IO.iodata_to_binary() |> List.wrap() |> Enum.reject(&(&1 == ""))

  defp translation(%Expo.Message.Plural{msgstr: msgstr}) do
    for {_form, text} <- Enum.sort(msgstr),
        text = IO.iodata_to_binary(text),
        text != "",
        do: text
  end
end
