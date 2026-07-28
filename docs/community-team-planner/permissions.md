# Permissions — Community Team Planner

## Permission identifiers

| Permission | Grants |
|---|---|
| `view_community_team_planner` | Open the Team Schedule index/show pages; read saved schedules visible to the user; trigger card drag/resize/reassign *requests* (the work-package data change itself is separately authorized — see below). |
| `manage_community_team_planner` | Create, rename, save configuration, change visibility, delete a schedule; add/remove/reorder rows. |

Both are registered under the `community_team_planner` project module
(`modules/community_team_planner/lib/open_project/community_team_planner/engine.rb`). Neither
permission, nor the module itself, carries an `enterprise_feature:` marker — see
`adr-001-independent-module.md`.

## What these permissions do **not** do

Neither permission grants any right to change work-package data. Every card mutation (drag,
resize, reassign) is authorized by `WorkPackages::UpdateContract` — the exact same contract the
work-package date picker and the REST API use — via `CommunityTeamPlanner::CardsController#update`
calling `WorkPackages::UpdateService`. Concretely, `WorkPackages::UpdateContract.update_allowed?`
requires at least one of: `edit_work_packages`, `assign_versions`, `change_work_package_status`,
`manage_subtasks`, `move_work_packages` on the work package's project. A user with
`view_community_team_planner` but none of those permissions can open the schedule and see cards,
but every drag/resize attempt is rejected by the contract and the card visually reverts (see
`CardsController`'s doc comment for how the revert works).

This is intentional and tested (`spec/permissions/team_schedules_permissions_spec.rb` and the
service/request specs) — the planner-level permission is never a substitute for work-package
permissions, matching the spec's Phase 3 requirement.

## Manage rights follow schedule ownership, not just the permission

Holding `manage_community_team_planner` is necessary but not sufficient to manage a *given*
schedule:

- A **private** schedule (`public: false`) is only manageable by its own `principal` (owner) — and
  since `TeamSchedule#visible?` also restricts a private schedule to its owner, it is not even
  visible to another user with `manage_community_team_planner`, let alone manageable.
- A **public** schedule is manageable by any project member holding
  `manage_community_team_planner`.

See `TeamSchedule#manageable?` and `TeamSchedules::BaseContract#user_allowed_to_manage`.

## Visibility scope

- `TeamSchedule.visible(user)` / `#visible?(user)`: `public? || principal == user`, and only for
  users holding `view_community_team_planner` on the schedule's project.
- Work packages shown on the grid are independently scoped to `WorkPackage.visible(current_user)`
  via the schedule's `effective_query` (a `::Query`, the same core scoping every work-package view
  uses) — a public *schedule* never exposes a work package the viewing user could not otherwise see.
  Cross-project card exposure is out of scope for the MVP (see `upgrade-guide.md` limitations);
  the query is always scoped to the schedule's own project.

## Server-side authorization is mandatory for every action

Every controller action in this module runs through `before_action :authorize` (core, checks the
current project's enabled modules and the user's role permissions against the engine's declared
action map) and, for schedule-config actions, an additional `authorize_manage` check
(`@team_schedule.manageable?(current_user)`). `CommunityTeamPlanner::CardsController` additionally
loads the target work package through `WorkPackage.visible(current_user)` before any update is
attempted, so a work package outside the user's visibility scope 404s rather than leaking existence
or being editable.
