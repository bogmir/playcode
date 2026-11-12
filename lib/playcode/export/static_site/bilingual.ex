defmodule Playcode.Export.StaticSite.Bilingual do
  @moduledoc """
  The site's interface in Spanish and English at once, Spanish by default. A text is
  printed in both, `<x-es>…</x-es><x-en>…</x-en>`, and style.css hides the one the page's
  `data-ui` does not name; an attribute is written in Spanish with its English in
  `data-en-<name>`, which site.js swaps in. Both come from gettext, the app's own
  translations, so a word reads the same here as on Playcode's pages. A text alike in both
  languages is printed once.

  Only the interface goes through here. What the play and its researchers wrote (its
  text, notes, headings, names) is printed as written, in its own language.
  """

  @backend PlaycodeWeb.Gettext

  @doc "A message as HTML in both languages: `t(\"Contents\")`."
  defmacro t(msgid, bindings \\ Macro.escape(%{})) do
    quote do
      unquote(__MODULE__).html(unquote(__MODULE__).tp(unquote(msgid), unquote(bindings)))
    end
  end

  @doc "A plural message as HTML in both languages."
  defmacro tn(msgid, plural, n, bindings \\ Macro.escape(%{})) do
    quote do
      unquote(__MODULE__).pair(fn ->
        require Gettext.Macros

        Gettext.Macros.ngettext_with_backend(
          unquote(@backend),
          unquote(msgid),
          unquote(plural),
          unquote(n),
          unquote(bindings)
        )
      end)
      |> unquote(__MODULE__).html()
    end
  end

  @doc "A message as the attributes `name` and `data-en-<name>`, for `<tag {ta(...)}>`."
  defmacro ta(name, msgid, bindings \\ Macro.escape(%{})) do
    quote do
      unquote(__MODULE__).attrs(
        unquote(__MODULE__).tp(unquote(msgid), unquote(bindings)),
        unquote(name)
      )
    end
  end

  @doc "A message in both languages, `{spanish, english}`, as plain text."
  defmacro tp(msgid, bindings \\ Macro.escape(%{})) do
    quote do
      unquote(__MODULE__).pair(fn ->
        require Gettext.Macros
        Gettext.Macros.gettext_with_backend(unquote(@backend), unquote(msgid), unquote(bindings))
      end)
    end
  end

  @doc "What `fun` returns in Spanish and in English, `{spanish, english}`."
  def pair(fun), do: {in_locale("es", fun), in_locale("en", fun)}

  @doc "What `fun` returns in each language, as HTML: `both(fn -> PlayLabels.… end)`."
  def both(fun), do: fun |> pair() |> html()

  @doc "Pairs joined with `separator`, each language's with its own."
  def join(pairs, separator) do
    {Enum.map_join(pairs, separator, &elem(&1, 0)), Enum.map_join(pairs, separator, &elem(&1, 1))}
  end

  defp in_locale(locale, fun), do: Gettext.with_locale(@backend, locale, fun)

  @doc "A pair as HTML: the text once when it is alike in both, else in both."
  def html({same, same}), do: same

  def html({es, en}),
    do: Phoenix.HTML.raw(["<x-es>", escape(es), "</x-es><x-en>", escape(en), "</x-en>"])

  @doc "A pair as the attribute `name`, its English in `data-en-<name>` when it differs."
  def attrs({same, same}, name), do: [{name, same}]
  def attrs({es, en}, name), do: [{name, es}, {"data-en-" <> name, en}, {"data-tr", true}]

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
