# Testing — Community Team Planner

## Running the module's tests

```bash
RAILS_ENV=test bundle exec rspec modules/community_team_planner/spec
```

This works with no extra configuration: the engine includes `OpenProject::Plugins::ActsAsOpEngine`,
which registers `modules/community_team_planner/spec` into `Rails.application.config
.plugins_to_test_paths` — the same mechanism `rake spec:plugins`, `rake spec:all`, and
`parallel_rspec` already use to discover every other bundled module's specs. No `.rspec` file or
custom spec helper was added; the module relies entirely on the root `spec/spec_helper.rb` /
`spec/rails_helper.rb`, exactly like `modules/team_planner` and `modules/resource_management` do.

To run the whole suite including this module:

```bash
RAILS_ENV=test bundle exec rake spec
# or, in parallel:
RAILS_ENV=test bundle exec rake parallel:spec
```

## Local environment note

This checkout's `.ruby-version` pins `4.0.2`, a patch release not available through `rbenv`/
`ruby-build` at the time this module was written (only `4.0.5`/`4.0.6` are published). Local
verification during development used `4.0.6` via a **temporary, uncommitted** edit to
`.ruby-version` — never staged or merged. `config/database.yml` (gitignored) pointed at a local
Postgres instance. Neither change is part of this module or should be replicated in CI, which
presumably has the exact pinned Ruby available.

## What is covered

| Layer | Location | Covers |
|---|---|---|
| Unit | `spec/models/team_schedules/visible_range_spec.rb` | Date-range calculation for all four display modes, including a non-default working-day configuration (Phase 5's "do not assume Saturday/Sunday are non-working"). |
| Unit | `spec/models/team_schedule_spec.rb` | `#visible?`, `#manageable?`, row add/remove/reorder, `display_mode`/`assignee_ids` validations. |
| Permission | `spec/permissions/team_schedules_permissions_spec.rb` | Every controller action is behind the declared permission — both the positive and negative case, via the shared `PermissionSpecs` helper used by `modules/team_planner`. |
| Service/Contract | `spec/services/team_schedules/*_spec.rb`, `spec/contracts/team_schedules/*_spec.rb` | Create/update/delete authorization rules (owner-only for private, manage-permission-gated for public), STI `type` handling. |
| Request | `spec/requests/team_schedules_spec.rb`, `spec/requests/cards_spec.rb` | End-to-end HTTP behavior: authentication, project scope, cross-project/unauthorized work-package access on the card endpoint, validation error surfacing. |
| Routing | `spec/routing/team_schedules_routing_spec.rb` | The `/projects/:project_id/team_schedule` URL namespace resolves to the expected controllers/actions. |

## What is intentionally not (yet) covered

Full browser-driven feature specs for drag/resize (Capybara + a JS driver actually dragging a
pointer across the grid) were not executed in this environment — running them requires headless
Chrome/Selenium, which was not verified to be available here. The drag/resize logic itself is
exercised indirectly: `CardsController` request specs cover the *server* half of every drag/resize
outcome (success, validation failure and rollback-to-truth, permission denial), which is the half
that can regress silently. `docs/development/running-tests/` documents the project's standard
Capybara setup for whoever adds the pointer-driven feature spec; it should assert:

- Dragging a card horizontally changes its date and preserves duration.
- Dragging a card to another row changes its assignee.
- Resizing from either handle changes only that edge's date.
- An invalid drop reverts the card and shows an error.
- Keyboard-only editing via the split view works as the non-mouse alternative (Phase 8).

## Reused test infrastructure

No bespoke factories beyond `spec/factories/team_schedule_factory.rb` (mirrors
`modules/resource_management/spec/factories/resource_planner_factory.rb`) and no bespoke matchers
or Capybara helpers were introduced — work packages, projects, and users all come from the core
factory suite (`create(:work_package, ...)`, `create(:project, ...)`, `create(:user, ...)`).
