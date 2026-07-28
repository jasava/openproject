# Architecture analysis — Community Team Planner ("Team Schedule")

Phase 0 deliverable for `feature/01_team_planner.md`. All findings below are grounded in the
actual checked-out repository state.

## Repository state

- Branch: `feature/jasava`, HEAD `2ba1fce1196` — exactly `v17.6.0` (0 commits ahead/behind the tag).
- Ruby pinned via `.ruby-version`: `4.0.2`. Rails: `~> 8.1.3` (`Gemfile:44`). Node: `^24.15.0`, npm `^11.0.0` (`package.json` engines).
- This checkout is a fork (`origin` = `jasava/openproject`) that already carries one extra bundled,
  **non-Enterprise** module not present in stock OpenProject: `modules/resource_management`
  ("Resource Planner"), added 2026‑05‑07. It is the closest architectural precedent in this
  codebase for Team Schedule — closer than `boards`, `calendar`, or `gantt` — and a new core model
  it introduces, `PersistedView`, is the persistence foundation this plan builds on. See "Data
  persistence recommendation" below.

## Relevant classes and file paths

| Concern | File(s) |
|---|---|
| Engine bootstrapping / plugin DSL | `lib/redmine/plugin.rb`, `lib/open_project/plugins/acts_as_op_engine.rb` |
| Module loading (bundled modules) | `Gemfile:420` (`eval_gemfile "./Gemfile.modules"`), `Gemfile.modules` |
| Enterprise-gated precedent (**do not reuse**) | `modules/team_planner/lib/open_project/team_planner/engine.rb`, `modules/team_planner/app/controllers/team_planner/team_planner_controller.rb:14` (`guard_enterprise_feature`), `app/controllers/concerns/accounts/enterprise_guard.rb`, `app/models/enterprise_token.rb` |
| Non-EE precedent module (primary template) | `modules/resource_management/**` |
| New core persistence model | `app/models/persisted_view.rb`, `app/models/persisted_query.rb`, `db/migrate/20260422081810_create_persisted_views.rb` |
| Classic persistence model (used elsewhere, also EE-safe but a worse fit) | `app/models/query.rb`, `app/models/view.rb`, `config/constants/views.rb`, `app/contracts/views/base_contract.rb` |
| Work package update path | `app/services/work_packages/update_service.rb`, `app/services/work_packages/set_attributes_service.rb`, `app/contracts/work_packages/{base,update}_contract.rb`, `app/services/work_packages/set_schedule_service.rb` |
| Working-day / scheduling math | `app/services/work_packages/shared/working_days.rb`, `app/models/day.rb`, `app/models/non_working_day.rb` |
| Split view (server page → WP details) | `app/helpers/work_packages/split_view_helper.rb`, `app/components/work_packages/split_view_component.html.erb`, `app/views/layouts/base.html.erb:145,180` (`content-bodyRight` Turbo Frame) |
| Filter form infra (non-Angular) | `app/components/filters/filter_form_component.rb`, `app/components/filter/filter_component.rb`, `frontend/src/stimulus/controllers/dynamic/filter/filters-form.controller.ts` |
| Drag-and-drop precedent | `frontend/src/stimulus/controllers/dynamic/generic-drag-and-drop.controller.ts` (dragula-based reorder/reparent) |
| Turbo Stream vocabulary | `app/controllers/concerns/op_turbo/component_stream.rb`, `app/components/op_turbo/stream_component.rb` |
| Table/grid ViewComponent base | `app/components/table_component.rb`, `app/components/op_primer/border_box_table_component.rb` |

## Reusable Community-edition abstractions

All of the following were grep-checked for `enterprise`/`EnterpriseToken`/`guard_enterprise_feature`
references and found clean:

- `Redmine::Plugin.register` + `project_module`/`permission`/`menu` DSL (`lib/redmine/plugin.rb`).
- `PersistedView` / `PersistedQuery` (new, generic, EE-agnostic — introduced for `resource_management`).
- `::Query` / `Queries::BaseQuery` / `Queries::Filters::*` (classic WP query & filter engine).
- `WorkPackages::UpdateService`, `SetAttributesService`, `BaseContract`, `UpdateContract`, `SetScheduleService`.
- `WorkPackages::Shared::WorkingDays`, `Day`, `NonWorkingDay`.
- `OpTurbo::ComponentStream` / `OpTurbo::Streamable` Turbo Stream vocabulary.
- `Filters::FilterFormComponent`.
- Split-view mechanism (`opce-wp-split-view` custom element + `content-bodyRight` Turbo Frame) — proven to work from a plain server-rendered page (`modules/boards` already does this from `layouts/base`, no Angular routing required).
- `frontend/src/stimulus/controllers/dynamic/generic-drag-and-drop.controller.ts` (dragula) for list-reorder-style interactions.
- `TableComponent`/`RowComponent` ViewComponent pattern.

## Enterprise-specific code that must NOT be depended upon

Four independent EE gates exist in `modules/team_planner`, all avoided by this plan:

1. `project_module :team_planner_view, enterprise_feature: "team_planner_view"` (engine.rb).
2. `menu ..., enterprise_feature: "team_planner_view"` on every team_planner menu entry.
3. `guard_enterprise_feature(:team_planner_view, ...)` in `TeamPlannerController`.
4. Direct `EnterpriseToken.allows_to?(:team_planner_view)` calls in `AddButtonComponent` and `MenusController`.

`community_team_planner` will: define entirely new permission/module/menu identifiers
(`community_team_planner_view`, `view_community_team_planner`, `manage_community_team_planner`),
never call `guard_enterprise_feature`/`EnterpriseToken`, never pass `enterprise_feature:` anywhere,
and never require/reopen anything under `modules/team_planner/**`.

## Proposed component diagram

```
modules/community_team_planner/
  lib/open_project/community_team_planner/engine.rb   # Redmine::Plugin.register: project_module, permissions, menu
  app/models/team_schedule.rb                          # < PersistedView (STI, table `persisted_views`)
  app/contracts/team_schedules/{base,create,update,delete}_contract.rb
  app/services/team_schedules/{create,update,delete,set_attributes}_service.rb
  app/services/team_schedules/cards/{move,resize}_service.rb   # wraps WorkPackages::UpdateService
  app/controllers/community_team_planner/{base,team_schedules,cards,rows}_controller.rb
  app/components/team_schedules/{table,row,grid,header,card}_component.rb(.html.erb)
  app/views/community_team_planner/team_schedules/{index,show,new}.html.erb
  config/routes.rb
  config/locales/en.yml
  db/migrate/*                                          # only helper tables if needed (none planned for MVP)
  frontend/... (none — no per-module JS pipeline in this codebase; Stimulus controllers instead live in
                the shared frontend/src/stimulus/controllers/dynamic/community-team-planner/ tree, mirroring
                how modules/resource_management's controllers are organized under dynamic/)
```

## Proposed request and update flows

**Read (grid render)**: `GET /projects/:id/team_schedule(/:team_schedule_id)` →
`TeamSchedulesController#show` → loads `TeamSchedule` (`PersistedView.visible`) → resolves
`effective_query` (`::Query`, scoped to visible/filtered work packages, assignee ∈ row list, date
range intersects visible window) → renders `TeamSchedules::GridComponent` (sticky assignee column +
horizontally scrolling date grid, CSS Grid + `position: sticky`, no calendar library).

**Reschedule (drag horizontal) / reassign (drag vertical) / resize**: card `mousedown`/`pointerdown`
→ custom Stimulus controller (no existing library fits 2-axis positioning + resize; documented as a
deliberate gap in "Existing native Hotwire drag-and-drop precedent") computes proposed
`start_date`/`due_date`/`assigned_to_id` from pixel deltas ÷ day-column width → optimistic DOM move →
`PATCH` to a narrow `Cards#update` action with `responseKind: 'turbo-stream'` (same
`@rails/request.js` `FetchRequest` pattern as `generic-drag-and-drop.controller.ts`) → controller
calls `WorkPackages::UpdateService.new(user:, model: work_package).call(start_date:, due_date:,
assigned_to_id:)` (exactly the path `date_picker_controller.rb` uses) → on failure, structured
`422` + card reverts; on success, turbo-stream replaces just the moved card.

**Schedule CRUD (create/rename/save/delete/visibility)**: `OpTurbo::ComponentStream` +
`Primer::Alpha::Dialog`, `TeamSchedules::{Create,Update,Delete}Service` wrapping `PersistedView`,
mirroring `ResourcePlanners::{Create,Update,Delete}Service` 1:1.

**Work-package details**: card subject link → `content-bodyRight` Turbo Frame → `opce-wp-split-view`
custom element, exactly as `modules/boards` already does from a plain `layouts/base` page. No new
details implementation.

## Data persistence recommendation

Use **`PersistedView`** (STI on the existing `persisted_views` table), not the classic `Query`/`View`
pair and not new bespoke tables:

- `TeamSchedule < PersistedView` gets `project`, `principal` (owner), `public`, favoriting
  (`acts_as_favoritable`), and `name` for free — directly satisfying most of Phase 2's persistence
  list with zero new migrations for those fields.
- `query` (polymorphic `belongs_to`) → `::Query.new_default(project:, user: principal)`, exactly the
  pattern `ResourceWorkPackageList#build_default_query` already uses — this **is** "Query filters"
  from Phase 2, reused directly, not reimplemented.
- `options` (jsonb, already on the table) stores: `display_mode` (`work_week`/`one_week`/`two_weeks`/`four_weeks`),
  `anchor_date` (date-range navigation position), `assignee_ids` (**ordered** array of principal IDs
  — this replaces the spec's suggested `community_team_planner_rows` table; array order **is** row
  order, and reordering is a single-array update instead of a join-table position rewrite).
- No new tables are planned for the MVP. This is a deliberate deviation from the spec's suggested
  `community_team_planner_views`/`community_team_planner_rows` schema, justified by the discovery
  that `PersistedView` — introduced in this fork after the spec's baseline assumptions — already
  solves the same problem more completely and with less new schema surface. If per-row metadata
  grows beyond a principal id (e.g. per-row color, collapse state), promoting `assignee_ids` to a
  child-`PersistedView` (`TeamSchedule::Row`) list, mirroring `UserCard`, remains a clean upgrade
  path without a data migration (the array can be read once and re-persisted as child rows).

Full schema/decision detail: `docs/community-team-planner/data-model.md` (Phase 2).

## Testing strategy

- Unit: `spec/models/team_schedule_spec.rb` (options/store_attribute, `visible?`), date-range/card-
  positioning helpers as plain Ruby unit specs.
- Contract: `spec/contracts/team_schedules/*_spec.rb` mirroring `modules/resource_management/spec`
  conventions (not yet listed above — will follow `modules/team_planner/spec/contracts` structure).
- Service: create/update/delete schedule, move/resize card (success + rollback).
- Request: permissions, project scope, validation errors, Turbo responses — mirrors
  `modules/team_planner/spec/requests/team_planner_spec.rb` and `modules/boards` request specs.
- Permission specs proving unauthorized/view-only/no-edit-permission/cross-visibility boundaries
  (Phase 3 requirement), modeled on `modules/team_planner/spec/permissions/view_team_planner_spec.rb`.
- Feature/system specs for create/navigate/drag/resize/save-reopen, using existing Capybara helpers
  and factories (no bespoke test infra).
- Run via `RAILS_ENV=test bundle exec rspec modules/community_team_planner/spec` — auto-discovered by
  `rake spec:plugins`/`spec:all` with zero extra config once the engine includes `ActsAsOpEngine`
  (confirmed via `Plugins::LoadPathHelper.spec_load_paths`).

## Upgrade-maintenance risks

- **Zero core file modifications are planned.** Everything lives under `modules/community_team_planner/`
  plus one line in `Gemfile.modules` to register the gem (unavoidable — nothing auto-loads `modules/*`).
- Depending on `PersistedView`/`PersistedQuery` ties this module's fate to that (new, actively-used-
  elsewhere) core abstraction rather than to Enterprise code — acceptable because `resource_management`
  already depends on it the same way, so it is de facto load-bearing core infrastructure now, not a
  fragile new dependency.
- No existing Hotwire drag+resize-by-pixel-delta component exists in this codebase; the custom
  Stimulus controller this module ships is new surface area with no upstream precedent to track for
  breakage — mitigated by keeping it small, well-tested, and independent of `generic-drag-and-drop`
  (so upstream changes to that shared controller cannot break this module).
- `permission`/`project_module` identifiers are global symbols; picking distinct names
  (`community_team_planner_view`, `view_community_team_planner`, `manage_community_team_planner`)
  avoids collision with `team_planner_view`/`view_team_planner`/`manage_team_planner` if both modules
  are ever bundled in the same install (they are, in this checkout).

Full component/permission/testing detail continues in the Phase-specific docs
(`data-model.md`, `permissions.md`, `testing.md`, `upgrade-guide.md`) as each phase lands.
