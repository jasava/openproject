# Performance analysis

Designed for the spec's stated scale: hundreds of projects, thousands of members, tens
of thousands of work packages, 30–100 rows on screen, a 4-week date range, 500–1,500
cards rendered at once.

## Query shape

Exactly one SQL query produces the grid's cards
(`GlobalTeamPlanner::QueryBuilder#scheduled_work_packages`):

- Starts from `effective_query.results.work_packages` — core's own filter/authorization
  pipeline, not a hand-rolled join.
- `.includes(:status, :type, :priority, :project, :assigned_to)` — the exact set of
  associations `CardComponent` reads, eager-loaded once rather than N+1'd per card
  (project name/identifier, status name, assignee name are all shown per card — see
  `feature/04_team_planner_rework.md`, "Cross-project work-package cards").
  `WorkPackage.visible` itself is a single `EXISTS` subquery against project/member
  scopes (see the `WITH member_projects AS (...)` CTE it compiles to), not a Ruby-side
  filter — it never loads "every work package the user can theoretically see" and
  filters in memory.
- `.where(assigned_to_id: row_ids)` narrows to exactly the view's row principals (plus
  `nil` when the Unassigned row is shown) — never "every work package in every visible
  project".
- The date-range predicate (`COALESCE(start_date, due_date) <= range_end AND
  COALESCE(due_date, start_date) >= range_start`) is applied in SQL, not by loading
  everything and filtering in Ruby.
- `unscheduled_by_row` (the "N without dates" count per row) is a separate `GROUP BY
  assigned_to_id .count` query, not computed from the already-loaded card list — it
  needs to count rows the main query's date filter deliberately excludes.

## Row/candidate list sizes

- `GlobalTeamPlannerView::MAX_ASSIGNEES` (30) and `MAX_SELECTED_PROJECTS` (200) bound how
  large a single view's row list / selected-project list can grow, validated on save
  (`assignee_ids_within_limit`/`selected_project_ids_within_limit`) — not enforced only
  in the UI.
- `project_candidates`/`principal_candidates` both `.limit(50)` — neither is paginated,
  both are "type to narrow down" autocompletes, not full listings. Widening the limit
  would need to come with actual pagination, not a larger single page.

## What is *not* cached across users

`WorkPackage.visible`/`Project.visible` are evaluated per-request against `User.current`
— there is no caching layer in this module that could return one user's authorized
result set to a different user. See `security.md` for why this matters beyond
performance.

## Known non-goals for the MVP

- No pagination/virtualization of the rendered grid itself — 30–100 rows × a few weeks of
  columns is within what a CSS-grid render handles directly. A view with more rows than
  `MAX_ASSIGNEES` is rejected at save time rather than silently rendered slowly.
- No warning banner for an "excessively broad" `all_visible` scope on an instance with
  hundreds of projects — flagged as a real gap, not implemented in this pass. The spec
  asks to "warn, don't silently truncate"; nothing here truncates, but nothing warns
  either yet.
