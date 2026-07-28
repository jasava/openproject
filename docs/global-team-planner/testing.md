# Test plan and coverage

All specs below were run against a real PostgreSQL test database with real HTTP
request/response cycles (`type: :rails_request`), not stubbed. Every number here reflects
an actual `rspec` run at the time of writing, not an estimate — re-run
`bundle exec rspec modules/global_team_planner/spec spec/migrations/migrate_team_schedules_to_global_team_planner_views_spec.rb`
to reproduce.

## `spec/migrations/migrate_team_schedules_to_global_team_planner_views_spec.rb` (5 examples)

Covers `up`/`down`/round-trip for the STI rename + `project_id` → `selected_project_ids`
conversion, including the "not a `TeamSchedule` row" and "zero rows" no-op cases. Builds
its legacy-row fixtures through a raw, non-STI-aware table class
(`self.inheritance_column = nil`) rather than the real (now-deleted) `TeamSchedule`
model class — deliberately, since the migration itself must work in production after
that model is gone, and the spec would be lying about that if its own fixtures depended
on the class still existing. See `data-model.md` for the `store_attribute` JSON-shape
subtlety this spec's fixtures had to account for.

## `modules/global_team_planner/spec/requests/global_team_planner_spec.rb` (23 examples)

Functional CRUD coverage: show (with/without a saved view, with the split view open,
public vs. private visibility), create/update/destroy, row add/remove, and the
"New work package" entry point's visibility/permission-gating and prefill params.

## `modules/global_team_planner/spec/requests/cards_spec.rb` (8 examples)

Drag/resize via `CardsController#update`: successful reschedule preserving duration,
rejection for a user without edit rights, 404 for a work package outside the visible
scope, reassignment (success and rejection for a non-assignable target), mass-assignment
protection (a forged `project_id`/`type_id` in the request body is ignored), and an
explicit cross-project case (one editor, cards in two different projects, only their own
project's card is reachable through the single shared drag endpoint).

## `modules/global_team_planner/spec/requests/cross_project_security_spec.rb` (11 examples)

The mandated leakage scenarios — see `security.md` for the full scenario list and the two
real bugs this suite caught before it was passing cleanly.

## What is deliberately not covered yet

- No system/Capybara/JS spec exercising actual drag-and-drop or the Stimulus
  project-picker/principal-picker interactively — coverage here is at the request-spec
  layer (the HTTP contract each Stimulus controller talks to), not the browser
  interaction layer.
- No dedicated spec for `GlobalTeamPlanner::VisibleRange` (date-math) beyond what the
  request specs exercise indirectly — it was ported verbatim from the old module's
  already-tested `TeamSchedules::VisibleRange`.
- No load/perf test at the "hundreds of projects, tens of thousands of work packages"
  scale described in `performance.md` — that analysis is by inspection of the query
  shape, not a benchmark run.
