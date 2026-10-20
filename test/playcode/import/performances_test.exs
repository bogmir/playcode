defmodule Playcode.Import.PerformancesTest do
  @moduledoc """
  What the performances import would write, from a sample of FileMaker's T10, T11 and T13
  with one version per rule (test/fixtures/filemaker/performances/regenerate.exs, whose
  header names the version behind each test). Writing the plan is tested through the mix
  task, in test/mix/tasks_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.ActivityLog
  alias Playcode.Bibliography
  alias Playcode.Import.Performances, as: Import
  alias Playcode.Performances
  alias Playcode.Performances.Performance

  @dump "test/fixtures/filemaker/performances"

  # The versions the sample holds; 83 stays out, for the version we do not hold.
  @held ~w(0010 0038 0209 0274 0304 0309 0313 0373 0379 0420 0472 0491 0644 0671 0675 0714)

  setup do
    plays = for code <- @held, do: play_fixture(%{"code" => "EMOTHE#{code}_Play"})

    {:ok, data} = Import.load(@dump)
    %{plays: plays, data: data}
  end

  defp plan(%{plays: plays, data: data}), do: Import.plan(data, plays)

  # The planned performance FileMaker's T11 row `id` makes.
  defp performance(plan, id), do: Enum.find(plan.performances, &(&1.ref == "T11:" <> id))

  # The work planned performance `id` cites, as the plan holds it.
  defp work(plan, id), do: plan.works[performance(plan, id).source]

  defp with_row(ctx, table, key, id, changes) do
    update_in(ctx, [:data, table], fn rows ->
      Enum.map(rows, &if(&1[key] == id, do: Map.merge(&1, changes), else: &1))
    end)
  end

  defp with_performance(ctx, id, changes),
    do: with_row(ctx, :performances, "_kp_IdObraRepresentacion", id, changes)

  defp with_source(ctx, id, changes),
    do: with_row(ctx, :sources, "_kp_IdFuenteInformacion", id, changes)

  defp play(ctx, code), do: Enum.find(ctx.plays, &(&1.code == "EMOTHE#{code}_Play"))

  # A planned performance's cast as `{surname, forename, nickname, sex, role}`.
  defp cast(performance) do
    for %{actor: actor, role: role} <- performance.cast do
      {actor["surname"], actor["forename"], actor["nickname"], actor["sex"], role}
    end
  end

  defp es(plan, key) do
    %{attrs: %{"names" => names}} = Enum.find(plan.places, &(&1.key == key))
    Enum.find_value(names, &(&1["language"] == "es" and &1["is_preferred"] and &1["name"]))
  end

  test "a performance's fields, as FileMaker wrote them", ctx do
    performance = performance(plan(ctx), "260")

    assert %{code: "EMOTHE0304_Play", ref: "T11:260", cast_from_cast_list: false} = performance
    assert performance.play_id == play(ctx, "0304").id

    assert performance.attrs == %{
             "date_text" => "1610",
             "venue" => "Globe or Blackfriars",
             "venue_type" => "commercial_theatre",
             "note" => "The play was reportedly hissed occasionally."
           }

    assert performance.company == "The King’s Men"
  end

  test "Wiggins's records are one work, each performance with its volume and page", ctx do
    plan = plan(ctx)
    performances = for p <- plan.performances, p.code == "EMOTHE0304_Play", do: p

    assert [wiggins] =
             performances |> Enum.map(& &1.source) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    assert length(performances) == 10

    # 312's NumVolTomo and page; 94 names its volume only in its title, "Volume 6: 1609-1616"
    assert %{source: ^wiggins, source_volume: "6", source_pages: "83"} = performance(plan, "263")
    assert %{source: ^wiggins, source_volume: "6", source_pages: nil} = performance(plan, "260")

    assert %{kind: "catalogue", pub_type: "book", year_text: "2012–"} =
             work = plan.works[wiggins].attrs

    assert work.monogr_author == "Wiggins, Martin, in association with Catherine Richardson"
    assert work.monogr_title == "British Drama 1533–1642: A Catalogue"
    assert {work.pub_place, work.publisher} == {"Oxford", "Oxford University Press"}
    assert "94" in plan.works[wiggins].records and "312" in plan.works[wiggins].records
  end

  test "a volume a title names in Roman numerals is read as a number", ctx do
    ctx =
      with_source(ctx, "94", %{
        "FueInf_Titulo2" => "British Drama 1533+1642: A Catalogue. Volume IX 1632-1636"
      })

    assert %{source_volume: "9"} = performance(plan(ctx), "260")
  end

  test "CATCOM's two records are one work, and its credit leaves the venue for the citation",
       ctx do
    plan = plan(ctx)

    assert performance(plan, "164").attrs["venue"] == "Casa de comedias de Toledo"

    # 0379 cites record 119 only, 0671 both
    assert %{source: :catcom} = performance(plan, "164")
    assert %{source: :catcom} = performance(plan, "377")
    assert %{records: ["119", "468"], attrs: catcom} = plan.works[:catcom]

    assert catcom.public_note ==
             "Copyright © DICAT Grupo de investigación teatral bajo Licencia Creative Commons BY-NC-ND."

    assert %{kind: "catalogue", url: "http://catcom.uv.es"} = catcom
  end

  test "Mora Sena's seven records are one work", ctx do
    plan = plan(ctx)

    # the imprint every one of the seven records names, through T13.1 and T13.2
    assert %{
             records: ~w(284 285 286 287 288 289 290),
             attrs: %{kind: "catalogue", pub_place: "New York", publisher: "Teneo Press"}
           } = plan.works[:restoration_comedy_1671]

    assert %{source: :restoration_comedy_1671, source_pages: "552"} = performance(plan, "248")
  end

  test "a source that is an edition S4 brought in cites that entry", ctx do
    for id <- ~w(116 385 418), do: entry_fixture("T04:" <> id)

    plan = plan(ctx)

    # record 97 on 0309's performance 131, 98 on 0472's 135, 81 on 0373's 32
    assert %{existing: "T04:116", records: ["97"]} = plan.works[performance(plan, "131").source]
    assert %{existing: "T04:385"} = plan.works[performance(plan, "135").source]
    assert %{existing: "T04:418"} = plan.works[performance(plan, "32").source]

    # where the performance sits in the edition is its own
    assert %{source_volume: "XIII", source_pages: "363"} = performance(plan, "32")
  end

  test "an edition S4 has not brought in is an entry of its own, from the record", ctx do
    plan = plan(ctx)

    assert %{existing: nil, attrs: %{pub_type: "scholarly_edition"}} =
             plan.works[performance(plan, "131").source]

    assert %{existing: nil, attrs: brome} = plan.works[performance(plan, "135").source]
    # Brome's address is a URL, not a note for researchers
    assert %{url: "https://www.dhi.ac.uk/brome/", note: nil} = brome
  end

  test "a record that is its own work keeps its pages", ctx do
    plan = plan(ctx)

    # Child's chapter in Wilson's Hamlet, on 0010's performance 23
    assert %{source_volume: nil, source_pages: nil} = child = performance(plan, "23")

    assert %{records: ["39"], existing: nil, attrs: attrs} = plan.works[child.source]
    assert %{pages: "lxix-xcvii", kind: "criticism", pub_type: "book_section"} = attrs
    assert attrs.analytic_author == "Child, Harold"
  end

  test "a lone record is a catalogue where the hand list says so", ctx do
    plan = plan(ctx)

    for id <- ~w(37 360 371), do: assert(%{kind: "catalogue"} = work(plan, id).attrs)

    # Harbage's Annals: FileMaker's note is for researchers
    assert work(plan, "37").attrs.note =~ "By Alfred Harbage"
    assert work(plan, "360").attrs.monogr_title =~ "Restoration Comedy 1660-1670"
    assert work(plan, "371").attrs.monogr_title == "The London Stage Database, 1660-1800"
  end

  test "FileMaker's note that is a series is one", ctx do
    plan = plan(ctx)

    # record 96, Neill's Renegado, on 0420's performance 130
    assert %{series: "Arden Early Modern Drama", note: nil} = work(plan, "130").attrs
  end

  test "record 479 is named, record 105 is reported", ctx do
    plan = plan(ctx)

    assert %{kind: "catalogue", monogr_title: "data.bnf.fr", url: url} = work(plan, "367").attrs
    assert url =~ "https://data.bnf.fr/"

    # 0209's performance 156 cites record 105, which T13 does not have
    assert %{source: nil, source_volume: nil, source_pages: nil} = performance(plan, "156")
    assert [skipped] = plan.skipped.source
    assert skipped =~ "EMOTHE0209_Play" and skipped =~ "T11:156" and skipped =~ "T13:105"
  end

  test "a record that names nothing is no source", ctx do
    nameless = %{
      "FueInf_Autor" => "",
      "FueInf_Titulo" => "",
      "FueInf_Autor2" => "",
      "FueInf_Titulo2" => ""
    }

    plan = ctx |> with_source("39", nameless) |> plan()

    # Child's chapter, on 0010's performance 23, loses its source
    assert %{source: nil} = performance(plan, "23")
    assert Enum.any?(plan.skipped.source, &(&1 =~ "T11:23" and &1 =~ "T13:39 names nothing"))
  end

  test "FileMaker's twin companies and actors are one", ctx do
    plan = plan(ctx)

    # The Duke's Company is records 30 and 52, Burbage 13 and 30; each plan names one
    assert "The Duke’s Company" in plan.merged_companies
    assert "Richard Burbage" in plan.merged_actors

    # a performance that names the unused twin names the same company, whatever its case
    twin =
      ctx
      |> with_performance("23", %{"_k_IdCompaniaNombre" => "52"})
      |> with_row(:companies, "_kp_IdCompaniaNombre", "52", %{
        "ComNom_NombreCompania" => "THE DUKE’S COMPANY"
      })

    assert performance(plan(twin), "23").company == "The Duke’s Company"
    assert Enum.count(plan(twin).companies, &(&1 == "The Duke’s Company")) == 1

    # 260's cast row for Armin names Burbage's other record: one actor, twice in the cast
    burbages =
      ctx
      |> with_row(:cast, "_kp_IdActorRepresentacion", "144", %{"_k_IdActorNombre" => "30|"})
      |> with_row(:actors, "_kp_IdActorNombre", "30", %{"ActNom_Apellidos" => "BURBAGE"})

    assert [{"Burbage", "Richard", nil, "man", nil}, {"Burbage", "Richard", nil, "man", nil}] =
             burbages |> plan() |> performance("260") |> cast()

    assert [_one] = Enum.filter(plan(burbages).actors, &(&1["surname"] == "Burbage"))
  end

  test "a twin with no sex takes the one its twin has", ctx do
    blank = with_row(ctx, :actors, "_kp_IdActorNombre", "13", %{"_k_IdActorSexo" => ""})
    cast = blank |> plan() |> performance("260") |> cast()

    assert {"Burbage", "Richard", nil, "man", nil} in cast
  end

  test "the cast, its actors and roles, the picker leftovers skipped", ctx do
    plan = plan(ctx)

    assert [
             {"Poquelin", "Jean François", "Molière", "man", "Argan"},
             {"M. de la Thorillière", nil, nil, "man", "Argan"}
           ] = plan |> performance("361") |> cast()

    # a forename alone is a stage name
    assert [{nil, nil, "Rosimond", "man", "Argan"}] = plan |> performance("364") |> cast()

    # actor and role kept in FileMaker's order, a woman's sex
    assert [
             {"Belleau", "Remy", nil, "man", "Cléopâtre"},
             {"Bastier de La Péruse", "Jean", nil, "man", "Octavien"}
           ] =
             plan |> performance("358") |> cast()

    # performance 358's first row names "1|Actor38|", 360's "14|Actor54|": picker leftovers
    assert [one, other] = plan.skipped.cast
    assert one =~ "EMOTHE0675_Play" and one =~ "T11:358" and one =~ "1|Actor38|"
    assert other =~ "EMOTHE0644_Play" and other =~ "T11:360" and other =~ "14|Actor54|"
  end

  test "a performance's place comes from T10, with its state", ctx do
    plan = plan(ctx)

    placed = for p <- plan.performances, p.place, do: p
    assert placed != []

    napoles = Enum.find(placed, &(es(plan, &1.place) == "Nápoles"))
    assert %{code: "EMOTHE0671_Play"} = napoles
    assert es(plan, napoles.state) == "Reino de Nápoles"

    # EMOTHE0379's performances name no place
    assert %{place: nil, state: nil} = performance(plan, "164")
  end

  test "The Way of the World's 1700 performance takes its cast from the cast list", ctx do
    plan = plan(ctx)

    assert %{ref: "T11:145", cast_from_cast_list: true, cast: []} = performance(plan, "145")
    assert [%{ref: "T11:145"}] = Enum.filter(plan.performances, & &1.cast_from_cast_list)
  end

  test "a performance with a venue type alone is undated and kept", ctx do
    plan = plan(ctx)

    assert %{attrs: %{"venue_type" => "street", "date_text" => nil}} = performance(plan, "26")
    assert Enum.any?(plan.skipped.undated, &(&1 =~ "EMOTHE0010_Play" and &1 =~ "T11:26"))
    refute Enum.any?(plan.skipped.undated, &(&1 =~ "T11:260"))
  end

  test "a performance that says nothing is skipped and reported", ctx do
    plan = plan(ctx)

    assert is_nil(performance(plan, "159"))
    assert [empty] = plan.skipped.empty
    assert empty =~ "EMOTHE0038_Play" and empty =~ "T11:159"
  end

  test "no planned performance is one the changeset would refuse", ctx do
    plan = plan(ctx)

    for performance <- plan.performances do
      attrs =
        Map.merge(performance.attrs, %{
          "play_id" => performance.play_id,
          "company_id" => performance.company && Ecto.UUID.generate(),
          "source_entry_id" => performance.source && Ecto.UUID.generate(),
          "source_volume" => performance.source_volume,
          "source_pages" => performance.source_pages
        })

      assert Performances.change_performance(%Performance{}, attrs).valid?,
             "#{performance.ref} is refused"
    end
  end

  test "FileMaker's placeholders are never copied into a field", ctx do
    ctx =
      ctx
      |> with_performance("260", %{
        "ObrRep_Nota" => "{Falta nota}",
        "ObrRep_NombreCircunstancia" => "{Falta lugar}",
        "_k_IdCompaniaNombre" => "99"
      })
      |> with_source("39", %{
        "FueInf_Titulo" => "{Falta título}",
        "FueInf_Pag" => "{Falta página}"
      })

    ctx =
      update_in(
        ctx,
        [:data, :companies],
        &[%{"_kp_IdCompaniaNombre" => "99", "ComNom_NombreCompania" => "{Falta compañía}"} | &1]
      )

    plan = plan(ctx)

    assert %{attrs: attrs, company: nil} = performance(plan, "260")
    assert %{"note" => nil, "venue" => nil} = attrs

    assert %{analytic_title: nil, pages: nil} = work(plan, "23").attrs
  end

  test "a version we do not hold is counted; a play already imported is skipped whole", ctx do
    assert %{not_held: 1, already_imported: []} = plan(ctx)

    {:ok, _} =
      Performances.create_performance(%{
        "play_id" => play(ctx, "0304").id,
        "date_text" => "1610",
        "origin" => "filemaker"
      })

    plan = plan(ctx)
    assert plan.already_imported == ["EMOTHE0304_Play"]
    assert Enum.all?(plan.performances, &(&1.code != "EMOTHE0304_Play"))
    assert performance(plan, "23")
  end

  test "the import's row in the activity log marks a play as imported, as its performances do",
       ctx do
    ActivityLog.log!(%{
      play_id: play(ctx, "0714").id,
      action: "import",
      resource_type: "play_performance",
      resource_id: play(ctx, "0714").id,
      metadata: %{"source" => "filemaker"}
    })

    plan = plan(ctx)

    assert plan.already_imported == ["EMOTHE0714_Play"]
    assert Enum.all?(plan.performances, &(&1.code != "EMOTHE0714_Play"))
  end

  test "what Playcode already has is reused", ctx do
    {:ok, _company} = Performances.find_or_create_company("the king’s men")

    {:ok, _actor} =
      Performances.find_or_create_actor(%{"surname" => "armin", "forename" => "robert"})

    plan = plan(ctx)

    assert "The King’s Men" in plan.reused_companies
    assert "The King’s Men" in plan.companies
    assert [%{"surname" => "Armin"}] = plan.reused_actors

    {:ok, entry} =
      plan.works[performance(plan, "260").source].attrs
      |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
      |> Bibliography.create_entry()

    again = plan(ctx)
    assert %{identical: id} = again.works[performance(again, "260").source]
    assert id == entry.id
  end

  test "the report says what it would write and what it left out", ctx do
    report = ctx |> plan() |> Import.report() |> Enum.join("\n")

    assert report =~ "EMOTHE0304"

    # 260 cites record 94, which names its volume and no page; 263's record has both
    assert report =~
             "1610  Globe or Blackfriars · Londres — Reino de Inglaterra · The King’s Men · commercial theatre  [Wiggins 6]\n"

    assert report =~
             "1610-11  Whitehall Palace · The King’s Men · commercial theatre  [Wiggins 6, 83]\n"

    assert report =~ "entries to create: 14"
    assert report =~ "companies merged: 2"
    assert report =~ "skipped, performances saying nothing: 1\n  EMOTHE0038_Play T11:159"
    assert report =~ "skipped, sources: 1\n  EMOTHE0209_Play T11:156: T13:105 is not in FileMaker"
    assert report =~ "performances on versions not held: 1"
  end

  test "a directory without the tables is an error naming the file" do
    assert {:error, {"T11_ObraRepresentacion.xml", :enoent}} =
             Import.load("test/fixtures/filemaker/witnesses")
  end
end
