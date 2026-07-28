# Data model

## `GlobalTeamPlannerView`

STI subclass of the core `PersistedView` (table `persisted_views`, discriminated by the
`type` column). `project_id` is always `nil` — there is no foreign key to a single project;
`validates :project, absence: true` enforces this at the model level. `parent` is likewise
always absent (`validates :parent, absence: true`) — a global view is never nested under
another view.

```
persisted_views
  id
  type                "GlobalTeamPlannerView"
  name
  project_id           NULL, always
  principal_id          -> the owner (User)
  query_id / query_type -> Query (polymorphic; always Query for this STI type)
  public                boolean — "Shared" in the UI (see permissions.md)
  favorited              via acts_as_favoritable
  options               jsonb — see below
```

### `options` (jsonb), via `store_attribute`

| key                    | type    | default        | meaning |
|------------------------|---------|----------------|---------|
| `display_mode`         | string  | `"one_week"`   | one of `GlobalTeamPlannerView::DISPLAY_MODES` |
| `anchor_date`          | date    | today          | the visible-range anchor |
| `assignee_ids`         | json    | `[]`           | ordered row principal IDs |
| `project_scope_mode`   | string  | `"all_visible"`| `all_visible` / `selected` / `my_projects` |
| `selected_project_ids` | json    | `[]`           | only meaningful when mode is `selected` |
| `show_unassigned`      | boolean | `false`        | show the trailing "Unassigned" row |
| `group_by_project`     | boolean | `false`        | reserved, not used by the MVP grid |

**A `store_attribute` serialization quirk worth knowing about**: when a sub-key is set
through its own generated setter (`view.selected_project_ids = [...]`, the normal path
taken by `GlobalTeamPlannerViews::SetAttributesService`/`BaseContract`), the gem writes
that value into the parent jsonb column as a **JSON-encoded string**, not a native nested
array — e.g. the raw column ends up containing `"selected_project_ids": "[3,7]"`, not
`"selected_project_ids": [3,7]`. Reading it back through the model's own generated getter
transparently decodes either shape, so application code never notices. But any code that
reads the raw `options` column directly — a migration, a report query, a `psql` shell —
must be prepared for **both** representations: a plain native JSON array (if the row was
last written via `update_columns`/a raw SQL path, as the `20260729090000` migration does)
or a JSON string nested inside the jsonb (if the row was last saved through the model).
`db/migrate/20260729090000_migrate_team_schedules_to_global_team_planner_views.rb#down`
and `GlobalTeamPlanner::QueryBuilder#build_scoped_query` both had to be written (or fixed)
with this in mind — see their comments for the concrete failure each one hit before the
fix. Also note: passing a whole `options:` hash directly into `.new`/`.create!` (rather
than through the individual generated setters) bypasses each sub-key's own `default:`
value entirely for any key not present in that hash — real application code never does
this (it always uses the individual setters), but test fixtures that want to simulate a
"legacy raw row" must supply every key the code will read, not rely on defaults.

### Migration from the old `TeamSchedule`

`db/migrate/20260729090000_migrate_team_schedules_to_global_team_planner_views.rb`
renames every existing `type: "TeamSchedule"` row to `type: "GlobalTeamPlannerView"`,
nulls out `project_id`, and seeds `project_scope_mode: "selected"` /
`selected_project_ids: [old_project_id]` so a converted view still shows exactly the one
project it always did — nothing regresses to "all projects" silently. `down` reverses this
exactly, as long as `selected_project_ids` was never edited afterward beyond its single
seeded ID (documented in the migration and covered by
`spec/migrations/migrate_team_schedules_to_global_team_planner_views_spec.rb`).

The migration's own helper class (`MigrationPersistedView`) sets
`self.inheritance_column = nil`. Without this, loading a `type: "TeamSchedule"` row
through *any* ActiveRecord class with a `type` column (not just the app's real
`PersistedView`/`TeamSchedule` classes) makes Rails try to `constantize("TeamSchedule")`
to decide which Ruby class to instantiate — which raises
`ActiveRecord::SubclassNotFound` once the old `community_team_planner` module (and its
`TeamSchedule` model file) is no longer bundled, exactly the state this migration must
still work correctly in. This was caught by writing the migration spec against a
database that actually contained `type: "TeamSchedule"` rows, rather than trusting that
"the migration ran without error" on an empty table proved anything.

## Other models touched

Nothing else changes shape. `Query`, `WorkPackage`, `Project`, `Principal`/`Member` are
all read through their existing scopes (`Query.new_default`, `WorkPackage.visible`,
`Project.visible`, `Member.assignable`) — see `security.md`.
