# Community Team Planner ("Team Schedule")

An independently-maintained, Community-edition project team-scheduling grid: project members as
rows, their work packages as date-range cards, with drag-to-reschedule, drag-to-reassign, resize,
and native work-package details integration.

This module is **not** OpenProject's Enterprise Team Planner (`modules/team_planner`). It is a
separate module with its own permissions, routes, models, and UI, built specifically to work
without an Enterprise license. See `adr-001-independent-module.md` for why it exists as a separate
module rather than a patch to the Enterprise one.

## What it does

- Project-level "Team Schedule" views, each a saved combination of: a name, public/private
  visibility, favorite/starred state, an ordered set of project-member rows, and a work-package
  filter query.
- A grid: sticky assignee column on the left, a horizontally-scrolling date range on the right,
  work-package cards positioned by start/finish date.
- Four date-range display modes: work week, 1 week, 2 weeks, 4 weeks — navigable backward, forward,
  and to today.
- Drag a card horizontally to reschedule it, vertically to reassign it, or both at once.
- Resize a card from either edge to change just its start or finish date.
- Click a card to open the work package in OpenProject's standard split view, with the schedule
  preserved in the background.
- Add/remove project members as schedule rows (this never modifies or unassigns any work package —
  it only changes what the *view* shows).

## What it does not do

- It does not touch, depend on, or expose the Enterprise Team Planner in any way.
- It does not create work packages by clicking/dragging empty grid cells, and it does not have a
  "search and add an existing work package" panel (spec Phase 10) — postponed as explicitly allowed
  by the task, since the MVP definition of done does not require it.
- It does not support cross-project rows or cards — one schedule is scoped to one project.
- It never writes to a work package except through OpenProject's own
  `WorkPackages::UpdateService`/`UpdateContract` — the same path the date picker and REST API use.
  See `permissions.md` for exactly what that means for authorization.

## Activating it for a project

1. Project settings → Modules → enable **Team schedule**.
2. Project settings → Roles & permissions → grant the roles that should use it **View team
   schedule** (read-only) and/or **Manage team schedule** (create/rename/delete/rows/visibility) —
   see `permissions.md` for exactly what each grants and does not grant.
3. A **Team Schedule** entry appears in the project menu once a role has `view_community_team_planner`.

## Creating a schedule

Project menu → Team Schedule → "Team schedule" button → name it (and, if you have
`manage_community_team_planner`, optionally make it visible to the rest of the project) → it opens
immediately with no rows yet. Use "Add member" to add project members as rows; drag or resize their
work-package cards to reschedule/reassign/resize.

## How work-package changes affect actual work-package data

Every drag, resize, and reassignment is a real, permanent change to the underlying work package —
there is nothing schedule-specific about the stored data. A card is never anything but a live view
of a `WorkPackage`'s `assigned_to`/`start_date`/`due_date`. Removing a row, renaming a schedule, or
deleting a schedule never changes any work package. Conversely, deleting or reassigning a work
package elsewhere in OpenProject (or from another schedule) is immediately reflected here, since
nothing is cached or duplicated.

## Running tests

```bash
RAILS_ENV=test bundle exec rspec modules/community_team_planner/spec
```

See `testing.md` for what is and is not covered.

## Disabling the module

Project settings → Modules → disable **Team schedule** (per project), or remove the
`openproject-community_team_planner` line from `Gemfile.modules` and re-bundle (instance-wide). See
`upgrade-guide.md` — neither action deletes any `TeamSchedule` or `WorkPackage` data.

## Known limitations

See `upgrade-guide.md`'s "Known limitations" section — no cross-project scope, no click/drag-to-
create work packages, no client-side row-reorder UI yet (the backend/service support it), and no
browser-driven (Capybara+JS) feature spec for the drag/resize interactions in this environment.

## GPL and attribution

Licensed GPL-3.0, consistent with the rest of OpenProject. This module was written from scratch
against this OpenProject checkout's existing abstractions (`PersistedView`, `WorkPackages::
UpdateService`, `OpTurbo`, ViewComponent/Stimulus conventions); no code was copied from
`modules/team_planner` (the Enterprise module) or any other Enterprise-tier source. Where this
module's structure closely mirrors an existing **non**-Enterprise module — `modules/
resource_management`, in particular its `ResourcePlanner`/dialog/contract/service patterns — that
is deliberate architectural reuse of an established, already-GPL-licensed pattern within the same
codebase, not a copy of its code.
