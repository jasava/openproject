# ADR 001: Global Team Schedule is an independent module, and a rework — not a fork — of the project-scoped prototype

## Status

Accepted. Supersedes `docs/community-team-planner/adr-001-independent-module.md` for this feature
(that document remains as the historical record of why the *first*, project-scoped version was
built independently of the Enterprise `modules/team_planner`; that reasoning is unchanged and
still applies — see "Independence from `modules/team_planner`" below).

## Context

The first version of this feature (`modules/community_team_planner`, "Team Schedule") was built
project-scoped: one saved schedule belonged to exactly one project, rows were that project's
members, and cards were that project's work packages. `feature/04_team_planner_rework.md`
requires a **global** planner: one page, outside any project, showing rows and cards aggregated
across every project the current user is authorized to see.

## Decision

Rename and rework `modules/community_team_planner` into `modules/global_team_planner`, in place —
not a second module living alongside the first. Concretely:

- The old module is deleted entirely: its project-module registration, its two
  project-scoped permissions, its project-sidebar menu, and its `/projects/:id/team_schedule`
  routes are all removed, not deprecated-in-place.
- The persistence layer is *kept and evolved*, not thrown away: `GlobalTeamPlannerView` is a new
  STI type on the same core `PersistedView` table `TeamSchedule` already used, with a real data
  migration renaming existing rows rather than orphaning them (see `data-model.md`).
- Every genuinely project-agnostic piece of the old implementation (the CSS-grid card-positioning
  math, the drag/resize Stimulus interaction, the `VisibleRange` date-window calculation, the
  Turbo Stream response patterns) is ported with its logic unchanged, only its namespace and
  constructor signatures updated.
- Every project-*scoped* piece (permission checks, query building, row/project selection, path
  helpers) is rewritten against OpenProject's existing global-scope primitives — see
  `data-model.md` and `security.md` for exactly which core APIs are reused and why no new
  authorization mechanism was invented.

## Why rework in place rather than keep both versions

The task's own framing ("Remove project-level assumptions from the earlier implementation... Do
not simply add an 'All projects' option on top of project-scoped architecture") rules out
layering a global mode on top of the old controller/routes/model. Keeping the old project-scoped
module running *alongside* a new global one was also rejected:

- It would mean two parallel, confusingly-similar "Team Schedule" menu entries and permissions,
  actively working against the spec's explicit "no project sidebar planner entry is required" and
  "the menu must not disappear when viewing All projects" requirements.
- The two would drift: bug fixes and UI improvements would need to land twice, and users would
  have to understand which one to use for which purpose, with no clear answer.
- Nothing in the old module's *data* needs preserving as project-scoped — the migration in
  `db/migrate/20260729090000_migrate_team_schedules_to_global_team_planner_views.rb` converts
  every existing saved schedule into an equivalent global view scoped to exactly the one project it
  always covered (`project_scope_mode: "selected"`, `selected_project_ids: [old_project_id]`), so
  no user-visible functionality regresses — a converted view still shows exactly what it showed
  before, just through the new data shape.

## Independence from `modules/team_planner` (unchanged from the original ADR)

This module still never calls `guard_enterprise_feature`, `EnterpriseToken`, or passes
`enterprise_feature:` anywhere in its own registration; still never requires, reopens, subclasses,
or monkey-patches any file under `modules/team_planner/**`. `modules/team_planner`'s own global
`overview` action (`TeamPlanner::TeamPlannerController#overview`) was read during Phase 0 research
purely to confirm the established *routing* convention for a global-plus-project-scoped module
(root-level `resources` alongside project-scoped ones in the same `config/routes.rb` — see
`routes-and-navigation.md`) — not copied, and not a functional dependency: `overview` is an index
of per-project saved views, not an aggregated cross-project grid, so it does not solve (and was
not treated as solving) this feature's actual cross-project query requirement.

## Consequences

- There is exactly one "Team Schedule" surface in the product at any time: the global one. No
  project module needs activating, no project admin needs to configure anything, and no old
  per-project schedule silently vanishes — it becomes a global view pre-scoped to that project.
- `global_team_planner` carries the same maintenance burden the original ADR already accepted for
  depending on `PersistedView`/`WorkPackages::UpdateContract`/etc. — shared with `resource_management`,
  the established precedent for a non-Enterprise bundled module built on those abstractions.
- The rollback path (`db/migrate/20260729090000_..._views.rb#down`) is exact only if a migrated
  view's `selected_project_ids` was never edited afterward beyond its single seeded project ID —
  documented explicitly in the migration and covered by a migration spec, per the task's "add
  migration and rollback tests" requirement.
