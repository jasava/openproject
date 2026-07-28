# Upgrade guide — Community Team Planner

## Core files touched

This module was built to minimize changes to OpenProject core, per the task's stated preference
order (new module files → supported registrations → small config changes → core patches as a last
resort). Exactly **two** existing core files were touched, both pure registrations with no logic
changes — no core file's *behavior* was altered:

### 1. `Gemfile.modules`

One line added inside the existing `:opf_plugins` group, alongside every other bundled module:

```ruby
gem 'openproject-community_team_planner', path: 'modules/community_team_planner'
```

**Why no extension point avoids this**: bundled modules are not auto-discovered by directory scan
— confirmed in Phase 0 by reading `lib/open_project/plugins/acts_as_op_engine.rb` and
`Gemfile.modules` itself. Every existing bundled module (`boards`, `resource_management`, etc.) is
registered the same way. This is the supported mechanism, not a workaround.

**Rebase risk**: near zero. A future `Gemfile.modules` rewrite would need to preserve or
re-add this one line; a merge conflict here is trivially resolvable (it cannot conflict with
unrelated modules' lines).

### 2. `frontend/src/global_styles/openproject.sass`

One `@import` line added among the existing "Module specific Styles" block:

```sass
@import "../../../modules/community_team_planner/app/components/_index.sass"
```

**Why no extension point avoids this**: every bundled module's component Sass is included the same
way — there is no dynamic/glob-based Sass loading in this codebase's asset pipeline (verified by
reading the file and finding one `@import` per module, including `resource_management`'s).

**Rebase risk**: near zero, same reasoning as above.

## Additive-only frontend registration

Two Stimulus controllers were added under
`frontend/src/stimulus/controllers/dynamic/team-schedule/` (`card.controller.ts`; a `grid`
controller was considered but turned out unnecessary — see the grid component's doc comment).
**No existing frontend file was modified for this.** `setup.ts` — the file that explicitly
`preregister`s most Stimulus controllers — was *not* touched, because
`OpApplicationController#fetchDynamicController` (`frontend/src/stimulus/controllers/
op-application.controller.ts`) already auto-loads any controller under `controllers/dynamic/` by
convention, resolving `data-controller="team-schedule--card"` to
`./dynamic/team-schedule/card.controller.ts` at runtime. Every other bundled module with its own
interactive Stimulus behavior (`admin`, `meetings`, `documents`, `costs`, `reporting`, `storages`,
etc.) already follows this exact same pattern — this module adds one more sibling directory, it
does not introduce the pattern.

## New module files (the bulk of the change)

Everything else lives entirely under `modules/community_team_planner/` — models, contracts,
services, controllers, ViewComponents, views, locales, and specs — plus the two new frontend files
named above. None of it is loaded unless `Gemfile.modules` includes the line above.

## No new database tables or migrations

`modules/community_team_planner/db/migrate/` does not exist. The module reuses the core
`persisted_views` table via Rails STI (`TeamSchedule < PersistedView`) — see `data-model.md` for
the reasoning. This means an upgrade of core OpenProject that changes `PersistedView`'s schema
(adds/removes columns, changes the `options` JSON shape assumptions elsewhere) is the main
forward-compatibility risk for this module, shared identically with `modules/resource_management`.

## Known limitations (MVP scope)

- Single-project scope only: `TeamSchedule#effective_query` is always built for one project;
  cross-project row/card inclusion (Phase 11's "Included projects" extension) is not implemented.
- "Create work package by clicking/dragging a cell" and "search and add an existing work package"
  (Phase 10) are not implemented — the MVP definition of done does not require them, and the task
  explicitly allows postponing Phase 10 if it would add significant complexity.
- Row reordering (drag-and-drop of assignee rows themselves, as opposed to reordering via the
  `assignee_ids` array on the server) has no dedicated UI yet — `TeamSchedule#reorder_rows` and the
  `reorder_rows` endpoint exist and are tested, but no client-side drag handle calls them yet.
- No dedicated browser-driven (Capybara + JS) feature spec for the drag/resize interactions — see
  `testing.md` for what *is* covered and why.

## Disabling the module

Standard OpenProject module deactivation applies: remove `community_team_planner` from a project's
enabled modules (Project settings → Modules), or drop the `openproject-community_team_planner`
gem line from `Gemfile.modules` and re-bundle to remove it instance-wide. Neither action touches
`persisted_views` rows belonging to other view types, and removing the gem does not delete any
`TeamSchedule`/`Query` data — it only stops the module's routes/UI from being reachable.
