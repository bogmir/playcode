defmodule Playcode.Export.StaticSite.Fingerprint do
  @moduledoc """
  Everything the static site's pages are built with except the play data, as one hash.
  `build.json` records the one a site was built with; when the current one differs, any
  page may be out of date, and Generate rebuilds every play.

  It covers the code (`module_info(:md5)` of `modules/0`), the English translations, the
  versions of the libraries that render and encode the pages, and the `:version` option.
  Not the files under `priv/static_site` (styles, scripts, fonts): no page embeds anything
  of them but their links, stamped with the start of their own hash, `assets/1`, so a
  change to them alone is copied and the stamps moved in place, not rebuilt. Not `build_date`: a page's footer says when that page
  was written. The play data is `plays.content_version`'s.

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
    Playcode.Export.NoteMarkup,
    Playcode.Export.TeiXml,
    Playcode.Bibliography,
    Playcode.Bibliography.Citation,
    Playcode.Bibliography.Entry,
    Playcode.Performances,
    Playcode.Performances.Actor,
    Playcode.Performances.Performance,
    Playcode.Statistics,
    Playcode.Statistics.Metrics,
    Playcode.Catalogue.Paratext,
    Playcode.Text,
    Playcode.Catalogue.Play,
    Playcode.PlayContent.InlineMarkup,
    Playcode.PlayContent.Element,
    Playcode.PlayContent.Note,
    Playcode.PlayContent.Note.Reading,
    Playcode.Places,
    Playcode.Places.Place,
    Playcode.Places.PlayPlace,
    Playcode.Witnesses,
    PlaycodeWeb.PlayLabels
  ]

  # StaticSite modules that shape no page: pushing the site, and this hash itself.
  @left_out [Playcode.Export.StaticSite.Deployer, __MODULE__]

  @libraries [:phoenix_live_view, :phoenix_html, :jason, :xml_builder]

  @doc """
  Every `Playcode.Export.StaticSite*` module but `left_out/0`, and the modules listed
  above. Read from the application's module list, not the loaded modules: in dev a module
  loads on first use, so a list of loaded ones would differ before and after the first
  build.
  """
  def modules do
    exported =
      Enum.filter(
        Application.spec(:playcode, :modules),
        &(String.starts_with?(Atom.to_string(&1), @prefix) and &1 not in @left_out)
      )

    Enum.sort(exported ++ @modules)
  end

  @doc "The StaticSite modules left out of `modules/0` because they shape no page."
  def left_out, do: @left_out

  @doc """
  A hex SHA-256 of what the pages are built with, for `opts[:version]`. `:gettext_dir`
  reads the translations from another directory than `priv/gettext`.
  """
  def current(opts) do
    code = Enum.map(modules(), &{&1, &1.module_info(:md5)})
    libraries = Enum.map(@libraries, &{&1, Application.spec(&1, :vsn)})
    gettext_dir = opts[:gettext_dir] || Application.app_dir(:playcode, "priv/gettext")

    hash({code, english(gettext_dir), libraries, opts[:version]})
  end

  @doc """
  A hex SHA-256 of the files under `priv/static_site`, by path and contents.
  `:assets_dir` reads them from another directory.
  """
  def assets(opts \\ []) do
    dir = opts[:assets_dir] || Application.app_dir(:playcode, "priv/static_site")

    dir
    |> Path.join("**")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map(&{Path.relative_to(&1, dir), File.read!(&1)})
    |> hash()
  end

  defp hash(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # The English translations that say something, by message: not the files, whose
  # source-line references move with every edit of the code. Parsing them takes ~35 ms and
  # the export page asks on every mount and form change, so the result is kept by the
  # files' contents: an edit is a new key, never a stale answer.
  # ponytail: never evicted, one entry per contents seen; a dev .po edit leaves the old one
  # until restart.
  defp english(gettext_dir) do
    files =
      gettext_dir
      |> Path.join("en/LC_MESSAGES/*.po")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&{Path.basename(&1), File.read!(&1)})

    key = {__MODULE__, :english, hash(files)}

    with nil <- :persistent_term.get(key, nil) do
      english = parse_english(files)
      :persistent_term.put(key, english)
      english
    end
  end

  defp parse_english(files) do
    files
    |> Enum.flat_map(fn {name, po} ->
      for message <- Expo.PO.parse_string!(po).messages,
          translation = translation(message),
          translation != [],
          do: {name, Expo.Message.key(message), translation}
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
