defmodule Playcode.ActivityLog do
  @moduledoc """
  Context for tracking admin actions (who did what, when, to which play).
  """

  import Ecto.Query
  alias Playcode.Repo
  alias Playcode.ActivityLog.Entry

  @per_page 50

  @doc """
  Inserts an activity log entry. Returns `{:ok, entry}` or `{:error, changeset}`.
  """
  def log(attrs) do
    %Entry{}
    |> Entry.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Fire-and-forget logging. Never raises or crashes the caller.
  """
  def log!(attrs) do
    log(attrs)
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end

  @doc """
  Returns a paginated, filtered list of activity log entries.

  ## Options
    * `:page` - page number (default 1)
    * `:per_page` - entries per page (default 50)
    * `:user_id` - filter by user
    * `:play_id` - filter by play
    * `:action` - filter by action type
    * `:resource_type` - filter by resource type
    * `:from` - filter entries from this datetime
    * `:to` - filter entries up to this datetime
  """
  def list_entries(opts \\ []) do
    page = opts[:page] || 1
    per_page = opts[:per_page] || @per_page
    offset = (page - 1) * per_page

    Entry
    |> apply_filters(opts)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^per_page)
    |> offset(^offset)
    |> preload([:user, :play])
    |> Repo.all()
  end

  @doc """
  Returns the count of entries matching the given filters.
  """
  def count_entries(opts \\ []) do
    Entry
    |> apply_filters(opts)
    |> Repo.aggregate(:count, :id)
  end

  defp apply_filters(query, opts) do
    query
    |> filter_by(:user_id, opts[:user_id])
    |> filter_by(:play_id, opts[:play_id])
    |> filter_by(:action, opts[:action])
    |> filter_by(:resource_type, opts[:resource_type])
    |> filter_from(opts[:from])
    |> filter_to(opts[:to])
  end

  defp filter_by(query, _field, nil), do: query
  defp filter_by(query, _field, ""), do: query
  defp filter_by(query, :user_id, id), do: where(query, [e], e.user_id == ^id)
  defp filter_by(query, :play_id, id), do: where(query, [e], e.play_id == ^id)
  defp filter_by(query, :action, action), do: where(query, [e], e.action == ^action)
  defp filter_by(query, :resource_type, rt), do: where(query, [e], e.resource_type == ^rt)

  defp filter_from(query, nil), do: query
  defp filter_from(query, ""), do: query

  defp filter_from(query, %DateTime{} = dt),
    do: where(query, [e], e.inserted_at >= ^dt)

  defp filter_from(query, date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        {:ok, dt} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
        where(query, [e], e.inserted_at >= ^dt)

      _ ->
        query
    end
  end

  defp filter_to(query, nil), do: query
  defp filter_to(query, ""), do: query

  defp filter_to(query, %DateTime{} = dt),
    do: where(query, [e], e.inserted_at <= ^dt)

  defp filter_to(query, date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        {:ok, dt} = DateTime.new(date, ~T[23:59:59.999999], "Etc/UTC")
        where(query, [e], e.inserted_at <= ^dt)

      _ ->
        query
    end
  end
end
