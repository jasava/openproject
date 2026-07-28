# ADR 001: Team Schedule is an independent module, not a change to Team Planner

## Status

Accepted.

## Context

OpenProject Community Edition ships `modules/team_planner`, a project-level scheduling view that is
gated behind the Enterprise `team_planner_view` feature via four separate mechanisms: a
`project_module ... enterprise_feature:` declaration, `menu ... enterprise_feature:` on every menu
entry, a `guard_enterprise_feature(:team_planner_view, ...)` controller filter, and direct
`EnterpriseToken.allows_to?(:team_planner_view)` calls in its components. Community-edition
installations without a valid Enterprise token can only reach that module's free upsell pages.

The request behind this work is a genuinely usable, Community-edition team scheduling grid:
project members as rows, work packages as date-range cards, with drag/resize/reassign.

## Decision

Build a new, independent bundled module, `modules/community_team_planner` ("Team Schedule"), that:

- Defines its own project module (`community_team_planner`), permissions
  (`view_community_team_planner`, `manage_community_team_planner`), menu key
  (`community_team_planner`), and URL namespace (`/projects/:id/team_schedule`) — none of which
  collide with `team_planner`'s identifiers.
- Never calls `guard_enterprise_feature`, `EnterpriseToken`, or passes `enterprise_feature:`
  anywhere in its own registration.
- Never requires, reopens, subclasses, or monkey-patches any file under `modules/team_planner/**`.
- Reuses only Enterprise-agnostic core infrastructure — confirmed by direct inspection, not
  assumption, in `docs/community-team-planner/architecture-analysis.md`: `PersistedView`,
  `::Query`, `WorkPackages::UpdateService`/`UpdateContract`/`SetScheduleService`,
  `WorkPackages::Shared::WorkingDays`, `OpTurbo`, and standard ViewComponent/Stimulus/Turbo
  patterns already used by other **non**-Enterprise bundled modules (`boards`,
  `resource_management`, `meeting`).

## Alternatives considered and rejected

**Patch `modules/team_planner` to bypass its Enterprise gate.** Rejected outright — this is
exactly the legal/architectural constraint the task explicitly forbids, independent of any
technical merits.

**Fork `modules/team_planner`'s code wholesale and strip the gate.** Rejected. Even with the gate
removed, this would still copy a module whose views, controllers, and (per the Phase 0 research)
Angular frontend were designed as Enterprise-tier surface area, and would create a large,
hard-to-maintain duplicate of core-adjacent code for a rebase to periodically reconcile. A from-
scratch module scoped to exactly the MVP requirement is smaller and has a clearer upgrade story
(see `upgrade-guide.md`).

**Extend the Enterprise `team_planner_view` permission/module to also work without a token.**
Rejected — this would make an existing Enterprise feature appear licensed, which the task
explicitly forbids, and would still leave the new module coupled to Enterprise-tier code paths for
no benefit.

## Consequences

- Two structurally similar but fully independent scheduling UIs can be installed side by side
  (as they are in this checkout, where `modules/team_planner` remains untouched). A site with a
  valid Enterprise token sees both "Team Planner" (Enterprise) and "Team Schedule" (Community) as
  distinct project modules; a site without one only has the latter.
- `community_team_planner` carries its own maintenance burden — future OpenProject core changes to
  `PersistedView`, `WorkPackages::UpdateContract`, etc. can affect it, but that risk is shared with
  `resource_management`, which is already bundled and depends on the same abstractions.
- No Enterprise licensing code, registration, or check was read for the purpose of copying its
  *mechanism* elsewhere — only to identify what to avoid depending on.
