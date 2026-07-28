# Security analysis

See `permissions.md` for the authorization model itself. This document covers the
specific cross-project leakage scenarios the spec required to be tested, how they're
covered, and two real bugs the implementation actually hit (and fixed) while building
this — kept here because both are exactly the kind of mistake this architecture is meant
to prevent, and both were only caught by testing against real, populated data rather than
by inspection.

## The authorization boundary, in one sentence

`WorkPackage.visible(current_user)` (chained unconditionally inside
`Query::Results#work_packages`) is the *only* thing that ever decides which work packages
a request can see. Every other piece of scoping in this module — `project_scope_mode`,
`selected_project_ids`, a saved view's filters, a forged `project_id`/`work_package_id`
in a request — only ever **narrows** what gets asked for. None of them can widen the
result past what `.visible` already allows, because none of them replace or bypass it.

## Required leakage scenarios and where they're covered

All of the following live in
`modules/global_team_planner/spec/requests/cross_project_security_spec.rb`, using two
users (`user_a`, `user_b`) with deliberately disjoint project membership:

- **A shared view referencing a project the current viewer can't see** never renders
  that project's name or work packages for that viewer, while still rendering the
  viewer's own accessible project's data correctly.
- **`effective_project_ids` is recalculated per viewer, including for the view's own
  owner** — owning a shared view is not a visibility grant. `user_a` (the owner) does not
  see `project_b` through their own view either, since they were never added to it.
- **A forged/invisible project ID in a saved-view filter update** does not error and does
  not leak — see the `PATCH update` example.
- **`project_candidates`/`principal_candidates` autocompletes** never return a project or
  principal the requester can't see, even when queried by the exact name/ID of something
  that exists.
- **Row-add and drag/resize with a forged/foreign ID** (a principal only assignable in an
  inaccessible project; a work package belonging to one) are rejected — `400`/`404`
  respectively — without mutating anything or revealing the target's existence.
- **A view whose `selected_project_ids` includes a project the current viewer has since
  lost access to** silently drops it from `effective_project_ids` rather than erroring
  or including it.

## Two real bugs this caught (not hypothetical)

### 1. `resources :views` silently routed to a nonexistent controller

`modules/global_team_planner/config/routes.rb`'s `scope "team_schedule",
controller: "global_team_planner/global_team_planner" do ... resources :views ... end`
looked correct but wasn't: Rails' `scope(controller:)` default does **not** apply to a
nested `resources` call's own controller inference — `resources :views` on its own
resolves to a root-namespace `ViewsController`, which doesn't exist. Every view
CRUD/toggle/row action (`new`, `create`, `edit`, `update`, `destroy`, `toggle_public`,
`add_row`, `remove_row`, `reorder_rows`) would have raised `NameError` at request time.
This was invisible to `rails routes` output at a glance and only surfaced by actually
grepping the generated controller column, then confirmed by running real request specs
against every one of those actions. Fixed by passing `controller:` explicitly to
`resources :views` too.

### 2. The project-scope filter used the wrong key, then over-corrected into invalidating the whole query

`GlobalTeamPlanner::QueryBuilder` narrows a "selected projects" view with
`query.add_filter(key, "=", project_ids)`. Two successive bugs here, both caught only by
a request spec that actually populated cross-project data and asserted on rendered HTML
(not by unit-testing the query builder in isolation):

- First attempt used `"project"` as the filter key. The real registered key for
  `Queries::WorkPackages::Filter::ProjectFilter` is `:project_id`
  (`self.key` in that class). An unregistered key resolves to
  `Queries::Filters::NotExistingFilter`, which matches nothing — the entire grid
  silently rendered zero cards, for every user, whenever `project_scope_mode` was
  anything but `all_visible`.
- Fixing the key to `"project_id"` and passing `selected_project_ids` through
  **unintersected** (reasoning: ".visible narrows it anyway, so an invisible ID is
  harmless") surfaced a second problem: `ProjectFilter` validates its *own* submitted
  values eagerly against `Project.visible.active`, and marks the *entire* query invalid
  — `Query#statement` short-circuits to the SQL literal `1=0` — if even one requested ID
  isn't visible. A shared view that legitimately selects one project the viewer can see
  and one they can't would take its *whole* query down, hiding the accessible project's
  work packages too — a functional regression, not a leak, but still wrong.
  Fixed by pre-intersecting the filter's candidate IDs with `Project.visible(user)` via
  `GlobalTeamPlannerView#effective_project_ids` (already the correct, existing
  recalculation method) before they ever reach `add_filter`. This is not a second
  authorization layer — `.visible` still independently enforces the real boundary at the
  work-package level regardless — it exists purely so an inaccessible ID doesn't corrupt
  the filter's own validation and disable the rest of the query.

Both bugs are now covered by regression tests (`cross_project_security_spec.rb`'s
"still renders the accessible project's own work packages for that viewer", and the full
CRUD suite in `global_team_planner_spec.rb`).

## What was deliberately *not* built as a separate check

- No planner-level "can view Team Schedule" permission gate beyond the entry check above
  — per-project/per-work-package permissions are the real boundary throughout.
- No pre-filtering of `assignee_ids` (row membership) against the current viewer's
  visible projects when *displaying* an already-saved row list — a shared view's row of
  named principals is informational (who the owner chose to track), not itself a project
  disclosure; only *adding* a new row is re-validated against the current viewer's
  authorized projects (see `permissions.md`).
