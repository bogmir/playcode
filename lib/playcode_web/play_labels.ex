defmodule PlaycodeWeb.PlayLabels do
  @moduledoc """
  Translated labels for the play metadata vocabularies.

  Lives here rather than in `Playcode.Catalogue.Play` because the labels are gettext
  strings and the schema has no business knowing about the web layer's locale, and
  rather than in a LiveView because the admin form and the public page need the same
  list. Later S2 fields — place of action, collection — add their vocabularies here.
  """

  use Gettext, backend: PlaycodeWeb.Gettext

  alias Playcode.Catalogue.Play
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
end
