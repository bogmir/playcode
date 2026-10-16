defmodule PlaycodeWeb.PlayLabels do
  @moduledoc """
  Translated labels for the play metadata vocabularies.

  Lives here rather than in `Playcode.Catalogue.Play` because the labels are gettext
  strings and the schema has no business knowing about the web layer's locale, and
  rather than in a LiveView because the admin form and the public page need the same
  list. Later S2 fields — place of action, collection — add their vocabularies here.
  """

  use Gettext, backend: PlaycodeWeb.Gettext

  alias Playcode.Bibliography.Entry
  alias Playcode.Catalogue.{Paratext, Play, PlaySource}
  alias Playcode.PlayContent.{Element, InlineMarkup, Note}
  alias Playcode.Places.{Place, PlayPlace}

  @doc "The Spanish-or-English name of a historical period slug."
  def historical_time_label("tiempo_indeterminado"), do: gettext("Indeterminate")
  def historical_time_label("antiguo_testamento"), do: gettext("Old Testament")
  def historical_time_label("edad_media"), do: gettext("Middle Ages")
  def historical_time_label("siglo_xv"), do: gettext("15th century")
  def historical_time_label("siglo_xvi"), do: gettext("16th century")
  def historical_time_label("siglo_xvii"), do: gettext("17th century")
  def historical_time_label("tiempo_maravilloso"), do: gettext("Marvellous (timeless)")
  def historical_time_label("antiguedad_clasica"), do: gettext("Classical antiquity")
  def historical_time_label("tiempo_alegorico"), do: gettext("Allegorical")
  def historical_time_label(_other), do: ""

  @doc "`{label, slug}` pairs for a select, blank first."
  def historical_time_options do
    [{"", nil} | Enum.map(Play.historical_times(), &{historical_time_label(&1), &1})]
  end

  @doc "The heading of a note of TEI `type`, as readers see it."
  def note_type_label("traductor"), do: gettext("Translator's note")
  def note_type_label("editor"), do: gettext("Editor's note")
  def note_type_label("editor_critico"), do: gettext("Critical editor's note")
  def note_type_label("editor_digital"), do: gettext("Digital editor's note")
  def note_type_label("autor"), do: gettext("Author's note")
  def note_type_label("variante"), do: gettext("Textual variant")
  def note_type_label(_other), do: gettext("Note")

  @doc """
  The type a note is filtered by: its own when it has a label (`Note.types/0`), else
  `"other"`, so the many types the corpus carries without one (`latinismo`,
  `falta_tipo`, …) are one plain Note, not several options that read the same. A variant
  is a key of its own.
  """
  def note_type_key("variante"), do: "variante"
  def note_type_key(type), do: if(type in Note.types(), do: type, else: "other")

  @doc """
  `{label, type}` pairs for a select: an untyped note first, then the corpus's types; and
  `current`, a type with no label of its own (`latinismo`, …), as itself, so saving a note's
  other fields does not drop its type.
  """
  def note_type_options(current \\ nil) do
    [{note_type_label(nil), ""} | Enum.map(Note.types(), &{note_type_label(&1), &1})]
    |> with_current(Note.types(), current)
  end

  @doc "The name of a kind of stage direction (`Element.stage_types/0`)."
  def stage_type_label("setting"), do: gettext("Setting")
  def stage_type_label("entrance"), do: gettext("Entrance")
  def stage_type_label("exit"), do: gettext("Exit")
  def stage_type_label("business"), do: gettext("Stage business")
  def stage_type_label("novelistic"), do: gettext("Narrative")
  def stage_type_label("delivery"), do: gettext("Delivery")
  def stage_type_label("modifier"), do: gettext("Character detail")
  def stage_type_label("location"), do: gettext("Location")
  def stage_type_label("mixed"), do: gettext("Mixed")

  @doc """
  `{label, kind}` pairs for a select: none first, then TEI's kinds; and `current`, a kind
  a file gave that is not among them, as itself, so saving the form does not drop it.
  """
  def stage_type_options(current \\ nil) do
    [{"", ""} | Enum.map(Element.stage_types(), &{stage_type_label(&1), &1})]
    |> with_current(Element.stage_types(), current)
  end

  @doc "The name of a paratext's kind (`Paratext.kinds/0`); a file's other word as itself."
  def kind_label("dedicatoria"), do: gettext("Dedication")
  def kind_label("epistola"), do: gettext("Epistle")
  def kind_label("introduccion_autor"), do: gettext("Author's address to the reader")
  def kind_label("prologo"), do: gettext("Prologue")
  def kind_label("argumento"), do: gettext("Argument")
  def kind_label("licencia"), do: gettext("Licence to print")
  def kind_label("noticia_representacion"), do: gettext("Performance notice")
  def kind_label("title_page"), do: gettext("Title page")
  def kind_label("head_title"), do: gettext("Head title")
  def kind_label("epilogo"), do: gettext("Epilogue")
  def kind_label("despedida"), do: gettext("Post-script")
  def kind_label("colofon"), do: gettext("Colophon")
  def kind_label("nota_edicion_digital"), do: gettext("Note on the digital edition")

  def kind_label("introduccion_editor_digital"),
    do: gettext("Introduction to the digital edition")

  def kind_label("introduccion_editor"), do: gettext("Editor's introduction")
  def kind_label("introduccion_traductor"), do: gettext("Translator's note")
  def kind_label("apendice"), do: gettext("Appendix")
  def kind_label("lugar_accion"), do: gettext("Scene of the action")
  def kind_label(kind), do: kind

  @doc """
  The kinds for a select, grouped: printed with the play, editorial texts, the scene of
  the action; and `current`, a kind a file gave that is not among them, as itself.
  """
  def kind_options(current \\ nil) do
    [
      {gettext("Printed with the play"), Paratext.printed_kinds()},
      {gettext("Editorial texts"), Paratext.editorial_kinds()},
      {gettext("Scene of the action"), ["lugar_accion"]}
    ]
    |> Enum.map(fn {group, kinds} -> {group, Enum.map(kinds, &{kind_label(&1), &1})} end)
    |> with_current(Paratext.kinds(), current)
  end

  defp with_current(options, known, current) do
    if current in [nil, ""] or current in known,
      do: options,
      else: options ++ [{current, current}]
  end

  @doc """
  A play's paratexts as printed, `{front, scene, back}`: those before the text; its scene
  of the action, printed after the cast list as emothe.uv.es prints it (with those before
  the text when the play has no cast list); and those after the text.
  """
  def split_paratexts(paratexts, divisions) do
    {back, front} = Enum.split_with(paratexts, & &1.back)

    {front, scene} =
      if Enum.any?(divisions, &(&1.type == "elenco")),
        do: Enum.split_with(front, &(not Paratext.scene?(&1.kind))),
        else: {front, []}

    {front, scene, back}
  end

  @doc "A paratext's name where one is needed: its heading, plain, or its kind's."
  def paratext_title(%{heading: heading}) when heading not in [nil, ""],
    do: InlineMarkup.plain(heading)

  def paratext_title(paratext), do: kind_label(paratext.kind)

  # The files' template values for a source's provenance: kept, as the file's, but no
  # reader is told them until the project says what they mean (question 27 in
  # docs/stakeholder/preguntas.html).
  @placeholder_provenances ["Texto base", "ProcedenciaFuente"]

  @doc "Where a source's digital text came from, as readers see it: nil for a placeholder."
  def provenance(%PlaySource{distributor: distributor})
      when distributor in @placeholder_provenances,
      do: nil

  def provenance(%PlaySource{distributor: distributor}), do: distributor

  @doc "The name of a play's form, as `Play.form/1` gives it."
  def form_label("verse"), do: gettext("Verse")
  def form_label("prose"), do: gettext("Prose")
  def form_label("mixed"), do: gettext("Verse and prose")

  @doc "The form select's options: automatic first, saying what it currently gives."
  def form_options(%Play{} = play) do
    automatic = Play.form(%{play | form: nil})

    [
      {gettext("Automatic (%{form})", form: form_label(automatic)), nil}
      | Enum.map(Play.forms(), &{form_label(&1), &1})
    ]
  end

  @doc "The Spanish-or-English name of a place type slug."
  def place_type_label("continent"), do: gettext("Continent")
  def place_type_label("country"), do: gettext("Country")
  def place_type_label("province"), do: gettext("Province")
  def place_type_label("region"), do: gettext("Region")
  def place_type_label("district"), do: gettext("District")
  def place_type_label("city"), do: gettext("City")
  def place_type_label("town"), do: gettext("Town")
  def place_type_label("building"), do: gettext("Building")
  def place_type_label("forest"), do: gettext("Forest")
  def place_type_label("river"), do: gettext("River")
  def place_type_label("lake"), do: gettext("Lake")
  def place_type_label("sea"), do: gettext("Sea")
  def place_type_label("island"), do: gettext("Island")
  def place_type_label("mountain"), do: gettext("Mountain")
  def place_type_label("other"), do: gettext("Other")
  def place_type_label(_other), do: ""

  def place_type_options, do: Enum.map(Place.types(), &{place_type_label(&1), &1})

  def place_role_label("setting"), do: gettext("Setting")
  def place_role_label("mentioned"), do: gettext("Mentioned")
  def place_role_label(_other), do: ""

  def place_role_options, do: Enum.map(PlayPlace.roles(), &{place_role_label(&1), &1})

  @editor_roles ~w(principal translator critical_editor researcher editor digital_editor reviewer)

  @doc "The Spanish-or-English name of a `play_editors.role`; an unknown one as stored."
  def editor_role_label("principal"), do: gettext("Principal investigator")
  def editor_role_label("translator"), do: gettext("Translator")
  def editor_role_label("critical_editor"), do: gettext("Critical edition editor")
  def editor_role_label("researcher"), do: gettext("Researcher")
  def editor_role_label("editor"), do: gettext("Editor")
  def editor_role_label("digital_editor"), do: gettext("Digital editor")
  def editor_role_label("reviewer"), do: gettext("Reviewer")
  def editor_role_label(role), do: role

  def editor_role_options, do: Enum.map(@editor_roles, &{editor_role_label(&1), &1})

  @doc """
  The name of a verse form as stored on `play_elements.verse_type`, or `"unmarked"`
  for a passage with no form; an unknown slug as stored. A `_tirada` (a run with no
  stanzas) is named by its form alone, as metrical synopses do.
  """
  def verse_form_label("redondilla"), do: gettext("Redondilla")
  def verse_form_label("quintilla"), do: gettext("Quintilla")
  def verse_form_label("decima"), do: gettext("Décima")
  def verse_form_label("romance"), do: gettext("Romance")
  def verse_form_label("romance_tirada"), do: gettext("Romance")
  def verse_form_label("romancillo_o_endecha"), do: gettext("Romancillo o endecha")
  def verse_form_label("octava_real"), do: gettext("Octava real")
  def verse_form_label("soneto"), do: gettext("Soneto")
  def verse_form_label("terceto"), do: gettext("Terceto")
  def verse_form_label("silva"), do: gettext("Silva")
  def verse_form_label("silva_tirada"), do: gettext("Silva")
  def verse_form_label("lira"), do: gettext("Lira")
  def verse_form_label("sexteto_lira"), do: gettext("Sexteto-lira")
  def verse_form_label("cancion"), do: gettext("Canción")
  def verse_form_label("cancion_canzone"), do: gettext("Canción")
  def verse_form_label("endecasilabos_sueltos_tirada"), do: gettext("Endecasílabos sueltos")
  def verse_form_label("verso_suelto"), do: gettext("Verso suelto")
  def verse_form_label("pareados"), do: gettext("Pareados")
  def verse_form_label("pareados_endecasilabos"), do: gettext("Pareados endecasílabos")
  def verse_form_label("pareado_hexasilabo"), do: gettext("Pareado hexasílabo")
  def verse_form_label("cuarteto"), do: gettext("Cuarteto")
  def verse_form_label("copla_arte_mayor"), do: gettext("Copla de arte mayor")
  def verse_form_label("copla_estructura_abierta"), do: gettext("Copla de estructura abierta")
  def verse_form_label("otro"), do: gettext("Otro")
  def verse_form_label("unmarked"), do: gettext("Unmarked")
  def verse_form_label(other), do: other

  @doc "The name of a metrical family from `Playcode.Statistics.Metrics.family/1`."
  def verse_family_label("romance"), do: gettext("Romance")
  def verse_family_label("spanish"), do: gettext("Spanish stanzas")
  def verse_family_label("italianate"), do: gettext("Italianate")
  def verse_family_label(_other), do: gettext("Other")

  @doc "The singular name of an act division type; an unknown one as stored."
  def act_label("acto"), do: gettext("Acto")
  def act_label("jornada"), do: gettext("Jornada")
  def act_label("act"), do: gettext("Act")
  def act_label("acte"), do: gettext("Acte")
  def act_label("play"), do: gettext("Play")
  def act_label("Jornada"), do: gettext("Jornada")
  def act_label("Act"), do: gettext("Act")
  def act_label(other), do: other

  @doc "The plural name of an act division type."
  def act_label_plural("acto"), do: gettext("Actos")
  def act_label_plural("jornada"), do: gettext("Jornadas")
  def act_label_plural("act"), do: gettext("Acts")
  def act_label_plural("acte"), do: gettext("Actes")
  def act_label_plural("play"), do: gettext("Plays")
  def act_label_plural("Jornada"), do: gettext("Jornadas")
  def act_label_plural("Act"), do: gettext("Acts")
  def act_label_plural(other), do: other <> "s"

  @doc "A kind's heading: the plural, as the bibliography groups it."
  def bibliography_kind_label("modern_edition"), do: gettext("Modern editions")
  def bibliography_kind_label("criticism"), do: gettext("Criticism")
  def bibliography_kind_label("translation"), do: gettext("Translations")
  def bibliography_kind_label("adaptation"), do: gettext("Adaptations")
  def bibliography_kind_label(_other), do: ""

  @doc "The kinds for a form's select: one entry is one of these."
  def bibliography_kind_options do
    [
      {gettext("Modern edition"), "modern_edition"},
      {gettext("Criticism"), "criticism"},
      {gettext("Translation"), "translation"},
      {gettext("Adaptation"), "adaptation"}
    ]
  end

  @doc "The witness types for a form's select, grouped as FileMaker's tree: manuscripts, then early editions."
  def witness_type_options do
    [
      {gettext("Manuscript"),
       [
         {gettext("Manuscript"), "manuscript"},
         {gettext("Autograph"), "autograph"},
         {gettext("Copy"), "copy"}
       ]},
      {gettext("Early edition"),
       [
         {gettext("Early edition"), "early_edition"},
         {gettext("Collection"), "collection"},
         {gettext("Collection of one author"), "collection_single_author"},
         {gettext("Collection of several authors"), "collection_several_authors"},
         {gettext("Suelta"), "loose"}
       ]}
    ]
  end

  @doc "A witness type's label, as the admin list shows it beside the siglum. Never public."
  def witness_type_label(type) do
    witness_type_options()
    |> Enum.flat_map(fn {_group, options} -> options end)
    |> Enum.find_value("", fn {label, value} -> if value == type, do: label end)
  end

  def pub_type_label("article"), do: gettext("Journal article")
  def pub_type_label("book_section"), do: gettext("Book chapter")
  def pub_type_label("scholarly_edition"), do: gettext("Scholarly edition")
  def pub_type_label("book"), do: gettext("Book")
  def pub_type_label("proceedings"), do: gettext("Conference proceedings")
  def pub_type_label("prologue"), do: gettext("Prologue")
  def pub_type_label("festschrift"), do: gettext("Festschrift")
  def pub_type_label("electronic"), do: gettext("Electronic publication")
  def pub_type_label("thesis"), do: gettext("Doctoral thesis")
  def pub_type_label("collection"), do: gettext("Collection")
  def pub_type_label(_other), do: ""

  def pub_type_options, do: Enum.map(Entry.pub_types(), &{pub_type_label(&1), &1})

  @doc "A translation group's heading."
  def bibliography_language_label(nil), do: gettext("Language not stated")
  def bibliography_language_label(code), do: Play.language_name(code)
end
