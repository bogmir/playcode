defmodule Playcode.Bibliography.Citation do
  @moduledoc """
  A bibliography entry as printed: FileMaker's elements and labels in one consistent order
  per kind, without its `{Falta …}` placeholders or doubled full stops. The order is in
  "Display" in docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  The admin page, `/plays/:code`, the static site and the sort order all go through
  `parts/2`, so they cannot drift apart. The labels are FileMaker's and are not
  translated.
  """

  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.PlayContent.InlineMarkup

  @doc """
  The citation as `%{text: binary, italic: boolean}` segments, as `InlineMarkup.parts/1`
  returns them, ending with `%{url: url, href: href}` when there is an address. `href` is
  the address only when it is http or https, so nothing else can become a link.
  """
  def parts(%Entry{} = entry, link \\ nil) do
    entry
    |> pieces(link)
    |> List.flatten()
    |> Enum.join(" ")
    |> InlineMarkup.parts()
    |> Kernel.++(url_parts(entry))
  end

  @doc "The citation as plain text."
  def plain(%Entry{} = entry, link \\ nil) do
    entry
    |> parts(link)
    |> Enum.map_join(fn
      %{url: url} -> url
      %{text: text} -> text
    end)
  end

  @doc "The citation as safe HTML: `<em>` for italics, `<a>` for an http(s) address, the rest escaped."
  def html(%Entry{} = entry, link \\ nil) do
    {:safe, entry |> parts(link) |> Enum.map(&segment_html/1)}
  end

  defp segment_html(%{href: href, url: url}) when is_binary(href),
    do: [~s(<a href="), escape(href), ~s(" rel="noopener">), escape(url), "</a>"]

  defp segment_html(%{url: url}), do: escape(url)
  defp segment_html(%{text: text, italic: true}), do: ["<em>", escape(text), "</em>"]
  defp segment_html(%{text: text}), do: escape(text)

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # --- Modern editions: Editors, ed. <<Title>>. Author. In: … ---

  defp pieces(%Entry{kind: "modern_edition"} = e, link) do
    analytic =
      edition_level(
        e.analytic_editors,
        e.analytic_title,
        e.analytic_author,
        e.analytic_translators
      )

    monogr =
      edition_level(e.monogr_editors, e.monogr_title, e.monogr_author, e.monogr_translators)

    [
      analytic,
      if(analytic != [] and monogr != [], do: "In:", else: []),
      monogr,
      edition(e.edition),
      with_value(volume_of(e, link), &"Vol. #{sentence(&1)}"),
      imprint(e, pages_of(e, link), "pp."),
      the_rest(e)
    ]
  end

  # --- Criticism, translations, adaptations: Author. "Title". Container. … ---

  defp pieces(%Entry{pub_type: "article"} = e, link) do
    [
      lead(e),
      edition(e.edition),
      [e.year_text, volume_of(e, link), e.issue, page_label(pages_of(e, link), "p.")]
      |> List.flatten()
      |> Enum.filter(&present?/1)
      |> join_sentence(),
      the_rest(e)
    ]
  end

  defp pieces(%Entry{} = e, link) do
    [
      lead(e),
      edition(e.edition),
      with_value(volume_of(e, link), &"Vol. #{sentence(&1)}"),
      imprint(e, pages_of(e, link), "p."),
      the_rest(e)
    ]
  end

  defp edition_level(editors, title, author, translators) do
    List.flatten([
      with_value(editors, &"#{&1}, ed."),
      with_value(title, &italic_sentence/1),
      with_value(author, &sentence/1),
      with_value(translators, &"Tra. #{sentence(&1)}")
    ])
  end

  # With an analytic level, the article or chapter leads and the book or journal follows.
  # A journal has no author line: FileMaker never printed one.
  defp lead(%Entry{} = e) do
    if present?(e.analytic_author) or present?(e.analytic_title) do
      [
        with_value(e.analytic_author, fn author ->
          if e.pub_type == "scholarly_edition", do: "#{author}, ed.", else: sentence(author)
        end),
        with_value(e.analytic_title, &~s("#{&1}".)),
        with_value(e.analytic_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.analytic_translators, &"Tra. #{sentence(&1)}"),
        if(e.pub_type == "article", do: [], else: with_value(e.monogr_author, &sentence/1)),
        with_value(e.monogr_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.monogr_title, &sentence/1),
        with_value(e.monogr_translators, &"Tra. #{sentence(&1)}")
      ]
    else
      [
        with_value(e.monogr_author, &sentence/1),
        with_value(e.monogr_title, &sentence/1),
        with_value(e.monogr_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.analytic_editors, &"Ed. #{sentence(&1)}"),
        with_value(e.monogr_translators, &"Tra. #{sentence(&1)}"),
        with_value(e.analytic_translators, &"Tra. #{sentence(&1)}")
      ]
    end
  end

  # Place: Publisher, Year, p. pages, N vols.
  defp imprint(e, pages, page_label) do
    place = [e.pub_place, e.publisher] |> Enum.filter(&present?/1) |> Enum.join(": ")

    [
      place,
      e.year_text,
      page_label(pages, page_label),
      with_value(e.volumes_total, &"#{&1} vols.")
    ]
    |> List.flatten()
    |> Enum.filter(&present?/1)
    |> join_sentence()
  end

  defp the_rest(e) do
    [
      with_value(e.series, &sentence/1),
      with_value(e.original_title, &"(Orig: #{&1})"),
      with_value(e.public_note, &sentence/1)
    ]
  end

  # "2nd" becomes "2nd ed."; "2nd ed" and "2nd ed." are left as typed.
  defp edition(value) do
    with_value(value, fn text ->
      if text =~ ~r/\bed\.?$/i, do: sentence(text), else: "#{text} ed."
    end)
  end

  defp page_label(pages, label), do: with_value(pages, &"#{label} #{&1}")

  # A link's volume and pages say where this play sits in the edition, so they win.
  defp volume_of(e, link), do: link_value(link, :volume) || e.volume
  defp pages_of(e, link), do: link_value(link, :pages) || e.pages

  defp link_value(%Link{} = link, key) do
    value = Map.get(link, key)
    if present?(value), do: value
  end

  defp link_value(_link, _key), do: nil

  defp url_parts(%Entry{url: url} = e) do
    if present?(url) do
      url = String.trim(url)
      href = if url =~ ~r{\Ahttps?://}i, do: url

      [%{text: " URL: ", italic: false}, %{url: url, href: href}] ++
        with_value(e.url_accessed_on, &%{text: " (acc. #{&1})", italic: false})
    else
      []
    end
  end

  defp join_sentence([]), do: []
  defp join_sentence(bits), do: bits |> Enum.map(&String.trim/1) |> Enum.join(", ") |> sentence()

  defp with_value(value, fun), do: if(present?(value), do: [fun.(String.trim(value))], else: [])

  defp sentence(text), do: if(stops?(text), do: text, else: text <> ".")

  # A title inside an italic title is set roman, as in print: FileMaker marks it with
  # <<…>>, so the title's markers are inverted rather than nested (nesting printed them).
  defp italic_sentence(title) do
    inverted =
      title
      |> InlineMarkup.parts()
      |> Enum.map_join(fn
        %{text: text, italic: true} -> text
        %{text: text} -> "<<#{text}>>"
      end)

    if stops?(InlineMarkup.plain(title)), do: inverted, else: inverted <> "."
  end

  defp stops?(text), do: String.ends_with?(text, [".", "?", "!"])

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
