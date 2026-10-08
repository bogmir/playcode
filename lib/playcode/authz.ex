defmodule Playcode.Authz do
  @moduledoc """
  The only place that answers "may this user do that?".

  Every route plug, LiveView mount hook and navigation item asks `can?/3`.
  Do not compare `user.role` anywhere else — a scattered role check is what
  produced an admin page (`/admin/users`) that no menu linked to, because the
  nav and the router had drifted apart.

  ## Extending to per-play scoping

  `can?/3` already receives the resource. To restrict researchers to plays
  they are assigned to, add a clause above the general researcher clause:

      def can?(%User{role: :researcher} = user, action, %Play{} = play)
          when action in @play_scoped_actions do
        active?(user) and assigned?(user, play)
      end

  plus a `play_assignments` join table and an assignment UI. No call site
  changes, because every caller already passes the resource it is acting on.
  """

  alias Playcode.Accounts
  alias Playcode.Accounts.User

  # `view_drafts` lets staff open an incomplete play on the public pages, which the
  # admin pages link to as a preview; everyone else gets a 404 there.
  @researcher_actions ~w(view_admin view_drafts manage_plays edit_content manage_editors
                         manage_sources manage_places manage_bibliography import_tei download_export
                         archive_play)a

  @admin_actions @researcher_actions ++
                   ~w(purge_play manage_users view_activity_log deploy_site
                      view_dashboard import_filemaker)a

  @doc """
  Returns true when `user` may perform `action`, optionally on `resource`.

  Inactive accounts — unconfirmed or deactivated — are denied everything.
  """
  def can?(user, action, resource \\ nil)

  def can?(%User{role: :admin} = user, action, _resource),
    do: Accounts.active?(user) and action in @admin_actions

  def can?(%User{role: :researcher} = user, action, _resource),
    do: Accounts.active?(user) and action in @researcher_actions

  def can?(_user, _action, _resource), do: false
end
