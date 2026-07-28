# frozen_string_literal: true

#-- copyright
# OpenProject Global Team Planner
# Copyright (C) the OpenProject community
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#++

module GlobalTeamPlanner
  # Builds the single authorized, date/assignee/project-bounded work-package
  # scope the grid renders from. This is the one place in the module that
  # decides "which work packages does this user see" — every other piece
  # (GridComponent, CardsController) reads through this class rather than
  # building its own scope, so the authorization boundary has exactly one
  # implementation.
  #
  # The authorization boundary itself is never reimplemented here: this
  # class only ever *adds filters* to a `::Query` built with `project: nil`
  # (see GlobalTeamPlannerView#build_default_query) — `Query::Results#
  # work_packages` unconditionally chains `.visible` (`WorkPackage.visible`)
  # regardless of what filters were requested, so a forged/no-longer-visible
  # project or work-package ID can never widen the result past what `user`
  # is actually authorized to see, even for `selected_project_ids` taken
  # directly from a shared, persisted view — see GlobalTeamPlannerView's
  # class comment. (The project_id *filter values* passed to the query are
  # still pre-intersected with `Project.visible` before use — see
  # `build_scoped_query` — but that is for the filter's own eager value
  # validation, not because `.visible` needs the help.)
  class QueryBuilder
    def initialize(view:, user: User.current)
      @view = view
      @user = user
    end

    # {principal_id => [work_package, ...]}, sorted by effective start date.
    def cards_by_row
      @cards_by_row ||= scheduled_work_packages.group_by(&:assigned_to_id).transform_values do |wps|
        wps.sort_by { |wp| effective_start(wp) }
      end
    end

    def unassigned_cards
      return [] unless @view.show_unassigned?

      scheduled_work_packages.select { |wp| wp.assigned_to_id.nil? }.sort_by { |wp| effective_start(wp) }
    end

    def unscheduled_count(principal_id)
      unscheduled_by_row[principal_id] || 0
    end

    def effective_start(work_package)
      work_package.start_date || work_package.due_date
    end

    def effective_finish(work_package)
      work_package.due_date || work_package.start_date
    end

    def for_range(visible_range)
      @visible_range = visible_range
      self
    end

    private

    attr_reader :view, :user

    def visible_range_value
      @visible_range || raise("QueryBuilder#for_range must be called before querying")
    end

    # `effective_query` is nil for a view that was never saved through
    # GlobalTeamPlanner::UpdateService (e.g. a brand-new, still-unsaved
    # default view) — render an empty grid rather than raising.
    def base_scope
      return WorkPackage.none if effective_query.nil?

      row_ids = view.assignee_ids.map(&:to_i)
      row_ids = row_ids + [nil] if view.show_unassigned?
      return WorkPackage.none if row_ids.empty?

      effective_query.results.work_packages
                     .includes(:status, :type, :priority, :project, :assigned_to)
                     .where(assigned_to_id: row_ids)
    end

    def effective_query
      @effective_query ||= build_scoped_query
    end

    # Applies the project-scope-mode as a normal "project_id" filter on top
    # of the view's own saved filters — never a separate authorization
    # layer, and `.visible` (applied by Query::Results regardless of
    # filters) still independently enforces authorization at the
    # work-package level either way. The filter key must be "project_id"
    # (Queries::WorkPackages::Filter::ProjectFilter.key) — an unregistered
    # key like "project" silently resolves to a NotExistingFilter that
    # matches nothing at all.
    #
    # The candidate IDs *are* pre-intersected with `Project.visible(user)`
    # here (via `view.effective_project_ids`, the same recalculation
    # `effective_project_ids`'s own callers rely on) rather than passed
    # through raw. This is not for authorization — it's because
    # Queries::WorkPackages::Filter::ProjectFilter validates its *own*
    # values eagerly against `Project.visible.active` and marks the whole
    # query invalid (Query#statement then short-circuits to the SQL literal
    # "1=0") if even one requested ID isn't visible. A shared view that
    # legitimately selects a project the current viewer cannot see would
    # otherwise take its *entire* query down with it, hiding every other
    # — otherwise fully visible — project's work packages too.
    def build_scoped_query
      query = view.effective_query
      return nil if query.nil?
      return query if view.project_scope_mode == "all_visible" # no extra filter needed, .visible already covers it

      query.tap { |q| q.add_filter("project_id", "=", view.effective_project_ids(user).map(&:to_s)) }
    end

    def scheduled_work_packages
      base_scope
        .where("start_date IS NOT NULL OR due_date IS NOT NULL")
        .where(
          "COALESCE(start_date, due_date) <= ? AND COALESCE(due_date, start_date) >= ?",
          visible_range_value.range_end, visible_range_value.range_start
        )
    end

    # `reorder(nil)` drops the ORDER BY inherited from the query's sort
    # criteria — PostgreSQL rejects a GROUP BY query whose ORDER BY
    # references a column that is neither grouped nor aggregated.
    def unscheduled_by_row
      @unscheduled_by_row ||= base_scope.reorder(nil).where(start_date: nil, due_date: nil)
                                        .group(:assigned_to_id).count
    end
  end
end
