# Routes and navigation

## Routes

No route in this module is nested under `/projects/:project_id`, and none takes a
`project_id` parameter anywhere — see `feature/04_team_planner_rework.md`, "Route
structure". Full table (`bundle exec rails routes | grep team_schedule`):

| Verb   | Path                                                    | Action                              |
|--------|----------------------------------------------------------|--------------------------------------|
| GET    | `/team_schedule`                                          | `global_team_planner#show`           |
| GET    | `/team_schedule/project_candidates`                        | `global_team_planner#project_candidates` |
| GET    | `/team_schedule/principal_candidates`                       | `global_team_planner#principal_candidates` |
| GET    | `/team_schedule/views`                                      | `global_team_planner#index`          |
| POST   | `/team_schedule/views`                                      | `global_team_planner#create`         |
| GET    | `/team_schedule/views/new`                                  | `global_team_planner#new`            |
| GET    | `/team_schedule/views/:id`                                  | `global_team_planner#show`           |
| PATCH/PUT | `/team_schedule/views/:id`                               | `global_team_planner#update`         |
| DELETE | `/team_schedule/views/:id`                                  | `global_team_planner#destroy`        |
| GET    | `/team_schedule/views/:id/edit`                             | `global_team_planner#edit`           |
| POST   | `/team_schedule/views/:id/toggle_public`                    | `global_team_planner#toggle_public`  |
| GET    | `/team_schedule/views/:id/rows/new`                         | `global_team_planner#new_row`        |
| POST   | `/team_schedule/views/:id/add_row`                          | `global_team_planner#add_row`        |
| DELETE | `/team_schedule/views/:id/rows/:principal_id`               | `global_team_planner#remove_row`     |
| PUT    | `/team_schedule/views/:id/reorder_rows`                     | `global_team_planner#reorder_rows`   |
| PUT    | `/team_schedule/work_packages/:work_package_id/schedule`    | `cards#update`                       |

The drag/resize endpoint is keyed only by `:work_package_id` — no view/schedule ID in the
URL at all, unlike the old project-scoped nested route
(`card_project_team_schedule_path`). The originating view is instead passed as an
optional `view_id` **body** parameter (mirroring how `anchor`/`mode` are already sent as
body params by the card Stimulus controller), used only to pick the right re-render
target/back-link — never as an authorization signal (see `security.md`).

### A routing pitfall worth remembering

`scope "team_schedule", controller: "global_team_planner/global_team_planner" do
resources :views ... end` looks like it should make every route under that block,
including the `resources` block, use that controller. It does **not** — `resources`
infers its own controller name (`views` → `ViewsController`) independently of the
enclosing scope's `controller:` default. The fix is to pass `controller:` explicitly to
`resources :views` as well. See `security.md` for how this was caught (every view CRUD
action would have 500'd/404'd at runtime; `rails routes` output alone didn't make the
mismatch obvious).

## Navigation

Registered on `Redmine::MenuManager`'s `:top_menu` (global nav), not `:project_menu` —
`modules/global_team_planner/lib/open_project/global_team_planner/engine.rb`:

```ruby
menu :top_menu,
     :global_team_planner,
     { controller: "/global_team_planner/global_team_planner", action: :show },
     caption: :label_global_team_planner,
     context: :modules,
     after: :work_packages,
     icon: "op-team-planner",
     if: ->(_) {
       (User.current.logged? || !Setting.login_required?) &&
         User.current.allowed_in_any_work_package?(:view_work_packages)
     }
```

No `project_module` block in the engine at all — there is nothing to "activate" per
project, and the menu item never disappears depending on which project (or no project)
the user is currently looking at, since it isn't scoped to one.

## Split-view integration

`GlobalTeamPlannerController#split_view_base_route` preserves the current view ID
(persisted or not), and every query param except the split-view-specific ones
(`work_package_split_view`, `work_package_id`, `tab`) — so closing the split view returns
to the same saved/unsaved view, the same `anchor`/`mode`, and the same filters, matching
the spec's "Split-view integration" requirement. `GlobalTeamPlanner::CardComponent`
builds its own split-view link the same way, always including `tab: "overview"`
explicitly (`WorkPackages::SplitViewHelper` calls `.to_sym` on `params[:tab]`
unconditionally — a missing tab param would raise, not fall back to a default).

## Work-package creation navigation

The "New work package" toolbar/row action (see `permissions.md`) is a plain full-page
link to core's `new_work_package_path` — deliberately **not** turbo-frame-scoped to the
split-view pane, since that route renders the entire Angular app shell, not a fragment.
