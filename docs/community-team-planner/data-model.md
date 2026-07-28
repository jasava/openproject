# Data model — Community Team Planner

## Decision: `PersistedView` STI, no new tables

`TeamSchedule < PersistedView` (table `persisted_views`, `type = "TeamSchedule"`). No new
migrations are added by this module for the schedule record itself.

`PersistedView` (core, `app/models/persisted_view.rb`, table created by
`db/migrate/20260422081810_create_persisted_views.rb`) already provides:

| Requirement (Phase 2) | Column / mechanism |
|---|---|
| Schedule name | `name` (string, required) |
| Project ID | `project_id` (FK) |
| Owner / creator | `principal_id` (FK to `users`) |
| Public/private visibility | `public` (boolean) |
| Favorite/starred state | `acts_as_favoritable` (join table, already wired) |
| Query filters | `query_id`/`query_type` (polymorphic) → `::Query` instance, reused as-is |
| Ordered assignee IDs, date-range mode, display prefs | `options` (jsonb) via `store_attribute` |

### `TeamSchedule#options` (jsonb) fields

| Key | Type | Default | Meaning |
|---|---|---|---|
| `display_mode` | string | `"one_week"` | one of `work_week`, `one_week`, `two_weeks`, `four_weeks` |
| `anchor_date` | date | creation date | left edge of the currently-saved visible range |
| `assignee_ids` | array of integers | `[]` | **ordered** principal IDs shown as rows; array order = row order |

### Why not the spec's suggested `community_team_planner_views` / `community_team_planner_rows` tables

The spec's Phase 2 fallback schema was written against the assumption that the only reusable
persistence layer is the classic `Query`/`View` pair. Repository inspection (Phase 0) found a
newer core abstraction, `PersistedView`, introduced in this fork specifically to support the
non-Enterprise `resource_management` module. It is Enterprise-agnostic (verified: no
`enterprise`/`EnterpriseToken` references anywhere in `persisted_view.rb`, `persisted_query.rb`, or
their contracts/services) and already solves ownership, visibility, favoriting, and filter-query
association generically. Building bespoke tables on top of it would duplicate columns
(`project_id`, `principal_id`, `public`, `name`) that already exist on `persisted_views`.

`assignee_ids` is a plain ordered array inside `options` rather than a `community_team_planner_rows`
join table with a `position` column because:

- Row count is small by design (Phase 13 target: 30 displayed assignees) — no query performance
  benefit to a separate indexed table at this scale.
- Reordering is a single JSON array rewrite (`update!(assignee_ids: new_order)`) instead of an
  N-row `position` repack (the pattern `resource_planner_views_controller.rb#repack_positions` needs
  precisely because *its* ordered collection — work packages in a list — can be large and independently
  queried; assignee rows are neither).
- It stays inside the single `persisted_views` row that `PersistedView#visible`/`favoritable`/`query`
  already govern, so no additional foreign-key/cascade-delete/authorization surface is introduced.

If a future need arises for per-row state beyond a principal ID (per-row color, per-row collapsed
state, per-row cross-project scoping), the documented upgrade path is to promote rows to child
`PersistedView` records (`TeamSchedule::Row < PersistedView`, `parent_id` → the `TeamSchedule`),
exactly mirroring `UserCard`/`ResourceWorkPackageList` as children of `ResourcePlanner`. This is a
non-breaking migration: `assignee_ids` can be read once and re-persisted as child rows without
touching the `TeamSchedule` record's identity, URL, or existing associations.

## Work packages are never duplicated

A schedule card always represents a live `WorkPackage` row, addressed by `work_package_id` at
render time via `TeamSchedule#effective_query.results` (scoped to visible work packages assigned to
one of `assignee_ids`, intersecting the visible date range). No card data is persisted independently
of the work package; deleting a `TeamSchedule` or removing a row never touches `WorkPackage` records.

## Model sketch

```ruby
class TeamSchedule < PersistedView
  DISPLAY_MODES = %w[work_week one_week two_weeks four_weeks].freeze

  store_attribute :options, :display_mode, :string, default: "one_week"
  store_attribute :options, :anchor_date,   :date
  store_attribute :options, :assignee_ids,  :integer, default: [], array: true

  validates :display_mode, inclusion: { in: DISPLAY_MODES }
  validates :project, presence: true
  validate :query_must_be_work_package_query

  after_initialize :set_defaults, if: :new_record?

  def visible?(user)
    return false if project.nil?
    return false unless user.allowed_in_project?(:view_community_team_planner, project)

    public? || principal == user
  end

  def build_default_query
    ::Query.new_default(project:, user: principal)
  end
end
```

Full contract/validation rules land with the Phase 3 permissions doc and the model/service code
itself; this file documents the schema decision, not the runtime behavior.
