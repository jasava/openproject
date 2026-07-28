# Permissions and authorization model

Team Schedule registers **zero new OpenProject permissions**. Every authorization
decision is made against permissions/scopes that already exist in core, applied at the
narrowest point that actually matters (a project, a work package, a saved view) rather
than at a single "can this user use the planner" gate.

## Entry gate: who can open `/team_schedule` at all

`GlobalTeamPlanner::GlobalTeamPlannerController#require_view_access!`:

```ruby
return if current_user.allowed_in_any_work_package?(:view_work_packages)
render "global_team_planner/global_team_planner/no_access", status: :forbidden, layout: "global"
```

`allowed_in_any_work_package?` is the exact method the CORE global "Work packages"
top-nav item already uses for its own `if:` condition
(`config/initializers/menus.rb`). Any user who can view a work package in at least one
project can open Team Schedule, with zero admin configuration — matching the spec's
explicit "preferred behavior" and avoiding a new permission that existing roles would
need to be manually granted (Rails' permission `dependencies:` is validation-only, not
auto-granting — see `app/contracts/roles/base_contract.rb`).

## What a view's `public`/private flag controls

`GlobalTeamPlannerView#visible?(user)`:

```ruby
def visible?(user)
  public? || principal == user
end
```

`public` is labelled "Shared" in the UI. A shared view's *configuration* (name, filters,
project scope, row list) is visible to anyone who passes the entry gate above — but its
*content* (which projects/work packages that configuration actually resolves to) is
always recalculated against the current viewer, never the owner. See `security.md`.

## Who can edit/delete/rename a view

`GlobalTeamPlannerView#manageable?(user)`:

```ruby
def manageable?(user)
  principal == user
end
```

Deliberately owner-only — unlike the old project-scoped `TeamSchedule`, which let anyone
holding a project "manage" permission edit a public schedule. A global view has no single
project whose permission could govern that, so "only the owner may change a shared view's
configuration" is the safe MVP default. `GlobalTeamPlannerViews::DeleteContract` makes one
exception: a site admin (`user.active_admin?`) may also delete any view, matching the
`::DeleteContract` base convention used elsewhere in the app.

## Per-work-package authorization (never planner-level)

Every action that touches a work package — viewing it on the grid, dragging/resizing it,
reassigning it — is authorized against **that work package's own project**, never against
"the user has Team Schedule access":

- **Visibility**: `GlobalTeamPlanner::QueryBuilder` builds its scope from
  `::Query#results.work_packages`, which unconditionally chains `WorkPackage.visible`
  regardless of what filters are applied. A card simply cannot appear unless the current
  user is separately authorized to view it in its own project.
- **Edit (drag/resize)**: `GlobalTeamPlanner::CardsController#update` loads the work
  package via `WorkPackage.visible(current_user).find(...)`, then calls
  `WorkPackages::UpdateService`/`WorkPackages::UpdateContract` — the exact same path the
  standard work-package edit form uses. That contract already checks
  `allowed_in_work_package?(user, work_package, :edit_work_packages)` against the work
  package's project, and `include UnchangedProject` structurally prevents `project_id`
  from ever being part of an update, so a card can never move between projects through
  this endpoint even by accident.
- **Reassignment**: the same `WorkPackages::UpdateContract` validates a submitted
  `assigned_to_id` via `Principal.possible_assignee(work_package)`
  (`WorkPackages::BaseContract#assignable_assignees`) — an assignee invalid for that
  work package's own project is rejected automatically, with no planner-specific logic
  needed.
- **Row add** (`GlobalTeamPlannerController#assignable_row_candidate?`) re-validates a
  candidate principal against `Member.assignable.of_project(...)` scoped to the view's
  *currently* authorized project set for *this* user — never against whatever the
  add-row dialog last rendered client-side.

## Autocomplete endpoints

`project_candidates` scopes to `Project.visible(current_user)`;
`principal_candidates` scopes to `Member.assignable.of_project(...)` intersected with the
requested (and re-validated) project IDs, falling back to the caller's own visible
projects if none of the requested IDs are accessible — never "all users". Both are
covered by `modules/global_team_planner/spec/requests/cross_project_security_spec.rb`.

## Work-package creation

The "New work package" entry point links to core's own project-agnostic
`new_work_package_path`, passing only optional `assignee_href`/`startDate` prefill query
params (read by the Angular new-work-package form) — never a project. Project choice,
the "only projects where this user can create" restriction, and assignee-vs-project
validation are all handled by the existing `WorkPackages::CreateContract`/Angular project
picker; this module adds no new authorization surface for creation, mirroring how it adds
none for editing. The button itself is gated by
`WorkPackage.allowed_target_projects_on_create(current_user).exists?` — the same scope
core's own "move to project" picker uses — so it never even offers to create when the
user has `add_work_packages` nowhere.
