defmodule Playcode.Export.TeiValidator do
  @moduledoc """
  Validates TEI-XML against the TEI P5 RelaxNG schema using xmllint.
  """

  @doc """
  Validates an XML string against the bundled TEI RelaxNG schema.

  Returns:
  - `{:ok, :valid}` — XML conforms to the TEI P5 schema
  - `{:error, :xmllint_not_found}` — xmllint is not installed
  - `{:error, :schema_not_found}` — schema file missing from priv/schemas/
  - `{:error, errors}` — validation failed; `errors` is a list of error strings
  """
  @spec validate(String.t()) :: {:ok, :valid} | {:error, atom()} | {:error, [String.t()]}
  def validate(xml) when is_binary(xml) do
    with [result] <- validate_all([xml]), do: result
  end

  @doc """
  Validates several XML strings with one xmllint, which compiles the schema (about 11 s,
  all of it CPU) once for all of them. Returns one result per string, in order, each as
  `validate/1` returns it; `{:error, atom()}` is the whole call's.
  """
  @spec validate_all([String.t()]) ::
          [{:ok, :valid} | {:error, [String.t()]}] | {:error, atom()}
  def validate_all([]), do: []

  def validate_all(xmls) when is_list(xmls) do
    with :ok <- check_xmllint(),
         :ok <- check_schema() do
      run_validation(xmls)
    end
  end

  defp schema_path do
    Application.app_dir(:playcode, "priv/schemas/tei_all.rng")
  end

  defp check_xmllint do
    case System.find_executable("xmllint") do
      nil -> {:error, :xmllint_not_found}
      _path -> :ok
    end
  end

  defp check_schema do
    if File.exists?(schema_path()) do
      :ok
    else
      {:error, :schema_not_found}
    end
  end

  defp run_validation(xmls) do
    dir = Path.join(System.tmp_dir!(), "tei-validate-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    paths = for i <- 1..length(xmls), do: Path.join(dir, "#{i}.xml")

    try do
      Enum.zip_with(paths, xmls, &File.write!/2)

      {output, _exit_code} =
        System.cmd("xmllint", ["--noout", "--relaxng", schema_path() | paths],
          stderr_to_stdout: true
        )

      lines = lines_by_file(output, paths)
      Enum.map(paths, &result(&1, Map.get(lines, &1, [])))
    after
      File.rm_rf(dir)
    end
  end

  # xmllint's lines grouped by the file they are about: a line naming a file opens its
  # run, and the lines after it (the source line and caret of a parser error) belong to it.
  defp lines_by_file(output, paths) do
    {_file, lines} =
      output
      |> String.split("\n", trim: true)
      |> Enum.reduce({nil, %{}}, fn line, {file, lines} ->
        file = Enum.find(paths, file, &names?(line, &1))
        {file, Map.update(lines, file, [line], &[line | &1])}
      end)

    Map.new(lines, fn {file, file_lines} -> {file, Enum.reverse(file_lines)} end)
  end

  defp names?(line, path),
    do: String.starts_with?(line, path <> " ") or String.starts_with?(line, path <> ":")

  defp result(path, lines) do
    if "#{path} validates" in lines do
      {:ok, :valid}
    else
      errors =
        lines
        |> Enum.reject(&(&1 == "#{path} fails to validate"))
        |> Enum.map(&String.replace(&1, path, "TEI-XML"))

      {:error, errors}
    end
  end
end
