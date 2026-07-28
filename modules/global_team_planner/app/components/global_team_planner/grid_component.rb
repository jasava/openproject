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

# Renders the schedule grid: a sticky assignee column on the left and a
# horizontally scrolling date grid on the right, with work-package cards
# positioned via CSS Grid column start/span (see grid_component.sass).
#
# Unlike the old project-scoped TeamSchedules::GridComponent, this component
# never builds any WorkPackage SQL itself — every authorized/date/assignee/
# project-bounded query lives in GlobalTeamPlanner::QueryBuilder (see
# #query_builder below), which this component only ever reads through. Its
# own job is purely rendering/layout math: which column a date falls in,
# which grid row a principal (or the Unassigned row) occupies, and the
# per-card `grid-column`/`grid-row` CSS.
#
# Card date handling (unchanged from the project-scoped version — see
# feature/04_team_planner_rework.md, "Global date-range query"):
# - both start and due date present: card spans start..due, clipped to the
#   visible range.
# - only one of the two is present: treated as a single-day card on that
#   date (matches how a milestone, which also has start == due, renders).
# - neither date is present: the work package is not placed on the grid.
#   `unscheduled_count` reports how many were hidden this way per row so the
#   UI is not silently incomplete.
module GlobalTeamPlanner
  class GridComponent < ApplicationComponent
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    DAY_COLUMN_OFFSET = 2 # column 1 is the sticky assignee column

    # Deliberately NOT named `anchor`: Rails' url_for treats an `anchor:`
    # option as the URL *fragment*, so `path(anchor: "2026-08-04")` silently
    # produces `/path#2026-08-04` instead of `/path?anchor=2026-08-04` — the
    # value never reaches the server as a param, and every date-range
    # navigation link becomes a no-op. (This bug was present in the original
    # project-scoped module too and was ported forward before being caught.)
    ANCHOR_PARAM = :anchor_date

    def initialize(view:, current_user:, params: {})
      super

      @view = view
      @current_user = current_user
      @params = params
    end

    attr_reader :view

    def wrapper_key
      "global-team-planner-#{@view.persisted? ? @view.id : 'new'}-grid"
    end

    def visible_range
      @visible_range ||= GlobalTeamPlanner::VisibleRange.new(display_mode:, anchor_date:)
    end

    def display_mode
      @display_mode ||= begin
        requested = @params[:mode].presence
        GlobalTeamPlannerView::DISPLAY_MODES.include?(requested) ? requested : @view.display_mode
      end
    end

    def anchor_date
      @anchor_date ||= begin
        requested = begin
          @params[ANCHOR_PARAM].presence && Date.parse(@params[ANCHOR_PARAM])
        rescue StandardError
          nil
        end
        requested || @view.anchor_date || Date.current
      end
    end

    delegate :days, to: :visible_range

    def working_days
      @working_days ||= WorkPackages::Shared::WorkingDays.new
    end

    def today
      Date.current
    end

    def rows
      @rows ||= @view.rows
    end

    # Whether the trailing "Unassigned" row should be rendered at all — see
    # feature/04_team_planner_rework.md, "Unassigned work packages".
    def unassigned_row?
      @view.show_unassigned?
    end

    # {principal_id => [work_package, ...]}, work packages intersecting the
    # visible range and sorted by effective start date for stable rendering.
    delegate :cards_by_row, to: :query_builder

    # Visible work packages with no assignee, intersecting the visible
    # range — only ever non-empty when `unassigned_row?` is true (see
    # GlobalTeamPlanner::QueryBuilder#unassigned_cards).
    delegate :unassigned_cards, to: :query_builder

    delegate :unscheduled_count, to: :query_builder

    def card_style(work_package, row_number)
      start_col = column_index(clipped_start(work_package))
      end_col = column_index(clipped_finish(work_package))
      "grid-column: #{start_col} / #{end_col + 1}; grid-row: #{row_number};"
    end

    # 1-based grid row for a given position in `rows` (row 1 is the header).
    def row_number(index)
      index + 2
    end

    # Grid row for the trailing "Unassigned" row, if shown — always the last
    # row, after every principal row.
    def unassigned_row_number
      rows.size + 2
    end

    # The grid row a work package's card belongs on in the *current*
    # rendering, or nil if it has none right now (e.g. reassigned to a
    # principal no longer among `rows`, or unassigned while the Unassigned
    # row is hidden). Used by GlobalTeamPlanner::CardsController to
    # re-render a single card after a drag/resize without re-rendering the
    # whole grid.
    def row_number_for(work_package)
      if work_package.assigned_to_id.nil?
        return unassigned_row_number if unassigned_row?

        return nil
      end

      index = rows.index { |principal| principal.id == work_package.assigned_to_id }
      index && row_number(index)
    end

    delegate :effective_start, to: :query_builder

    delegate :effective_finish, to: :query_builder

    def non_working_day?(date)
      !working_days.working?(date)
    end

    # Whether the current user can create a work package in at least one
    # project at all — gates the toolbar's "New work package" entry point.
    # Reuses the exact scope core's own "create work package"/"move to
    # project" pickers use (see WorkPackage.allowed_target_projects_on_create)
    # rather than reimplementing an "any project with add_work_packages"
    # check — see feature/04_team_planner_rework.md, "Global work-package
    # creation": "only show projects where the user is authorized to create
    # work packages".
    def can_create_work_packages?
      return @can_create_work_packages unless @can_create_work_packages.nil?

      @can_create_work_packages = WorkPackage.allowed_target_projects_on_create(@current_user).exists?
    end

    # Links straight to core's own global "new work package" page rather
    # than a module-specific project-picker dialog: that page already
    # requires the user to explicitly choose a project (never silently
    # picks one), already restricts the choice to projects the user may
    # create work packages in, and already validates the chosen assignee
    # against whichever project is picked (the normal WorkPackages::
    # CreateContract path) — so this module adds zero new authorization
    # surface for creation, exactly like it does for editing. `assignee`
    # and the visible range's start date are passed through as optional
    # prefill query params the Angular new-work-package form already reads
    # (see frontend/.../wp-new-split-view.component.ts) — never as a
    # project or an assumption about which project is "first".
    def new_work_package_url(assignee: nil)
      query = {}
      query[:assignee_href] = helpers.api_v3_paths.user(assignee.id) if assignee
      query[:startDate] = visible_range.range_start.iso8601

      helpers.new_work_package_path(**query)
    end

    def nav_url(anchor:, mode: display_mode)
      params = { ANCHOR_PARAM => anchor.iso8601, :mode => mode }

      if @view.persisted?
        helpers.global_team_planner_view_path(@view, **params)
      else
        helpers.global_team_planner_path(**params)
      end
    end

    # Global empty states (feature/04_team_planner_rework.md, "Global empty
    # states") — each condition gets its own message rather than one
    # generic blank grid. Checked in this order by the template: a missing
    # project/team-row precondition always wins over "nothing in this date
    # range", since fixing the precondition is the more useful next step.

    def no_accessible_projects?
      Project.visible(@current_user).none?
    end

    def no_selected_projects?
      @view.project_scope_mode == "selected" && @view.effective_project_ids(@current_user).empty?
    end

    def no_team_rows?
      rows.empty? && !unassigned_row?
    end

    # Projects and rows are fine, but nothing in the currently visible date
    # range matched. Covers both the spec's "no work packages in range" and
    # "filters remove all results" cases with one message: QueryBuilder
    # does not expose enough to tell those two apart without an extra query
    # that would otherwise never be needed.
    def no_matching_work_packages?
      return false if no_accessible_projects? || no_selected_projects? || no_team_rows?

      cards_by_row.values.all?(&:blank?) && unassigned_cards.blank?
    end

    private

    def query_builder
      @query_builder ||= GlobalTeamPlanner::QueryBuilder.new(view: @view, user: @current_user).for_range(visible_range)
    end

    def clipped_start(work_package)
      [effective_start(work_package), visible_range.range_start].max
    end

    def clipped_finish(work_package)
      [effective_finish(work_package), visible_range.range_end].min
    end

    def column_index(date)
      idx = days.index(date)
      # A clipped date might fall on a day skipped by `work_week` mode (e.g. a
      # card spanning a weekend); snap to the nearest visible column instead
      # of erroring, so partially-visible cards still render.
      idx = days.index { |d| d >= date } || (days.length - 1) if idx.nil?
      idx + DAY_COLUMN_OFFSET
    end
  end
end
