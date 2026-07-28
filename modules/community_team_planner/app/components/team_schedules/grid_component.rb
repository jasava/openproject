# frozen_string_literal: true

#-- copyright
# OpenProject Community Team Planner
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
# Card date handling (Phase 5 requirement to define behavior per case):
# - both start and due date present: card spans start..due, clipped to the
#   visible range.
# - only one of the two is present: treated as a single-day card on that
#   date (matches how a milestone, which also has start == due, renders).
# - neither date is present: the work package is not placed on the grid.
#   `unscheduled_count` reports how many were hidden this way per row so the
#   UI is not silently incomplete.
module TeamSchedules
  class GridComponent < ApplicationComponent
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    DAY_COLUMN_OFFSET = 2 # column 1 is the sticky assignee column

    def initialize(team_schedule:, project:, params: {})
      super

      @team_schedule = team_schedule
      @project = project
      @params = params
    end

    def wrapper_key
      "team-schedule-#{@team_schedule.id}-grid"
    end

    def visible_range
      @visible_range ||= TeamSchedules::VisibleRange.new(display_mode:, anchor_date:)
    end

    def display_mode
      @display_mode ||= begin
        requested = @params[:mode].presence
        TeamSchedule::DISPLAY_MODES.include?(requested) ? requested : @team_schedule.display_mode
      end
    end

    def anchor_date
      @anchor_date ||= begin
        requested = begin
          @params[:anchor].presence && Date.parse(@params[:anchor])
        rescue StandardError
          nil
        end
        requested || @team_schedule.anchor_date || Date.current
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
      @rows ||= @team_schedule.rows
    end

    # {principal_id => [work_package, ...]}, work packages intersecting the
    # visible range and sorted by effective start date for stable rendering.
    def cards_by_row
      @cards_by_row ||= scheduled_work_packages.group_by(&:assigned_to_id).transform_values do |wps|
        wps.sort_by { |wp| effective_start(wp) }
      end
    end

    def unscheduled_count(principal_id)
      unscheduled_by_row[principal_id] || 0
    end

    def card_style(work_package, row_number)
      start_col = column_index(clipped_start(work_package))
      end_col = column_index(clipped_finish(work_package))
      "grid-column: #{start_col} / #{end_col + 1}; grid-row: #{row_number};"
    end

    # 1-based grid row for a given position in `rows` (row 1 is the header).
    def row_number(index)
      index + 2
    end

    def effective_start(work_package)
      work_package.start_date || work_package.due_date
    end

    def effective_finish(work_package)
      work_package.due_date || work_package.start_date
    end

    def non_working_day?(date)
      !working_days.working?(date)
    end

    def nav_url(anchor:, mode: display_mode)
      helpers.project_team_schedule_path(@project, @team_schedule, anchor: anchor.iso8601, mode:)
    end

    private

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

    # `effective_query` is nil for a schedule that was never routed through
    # TeamSchedules::(Create|SetAttributes)Service (e.g. built directly in a
    # test, console, or a future import path) — the model layer intentionally
    # allows a nil query (see TeamSchedule#query_must_be_work_package_query),
    # so render an empty grid rather than raising.
    def base_scope
      return WorkPackage.none if @team_schedule.effective_query.nil?

      @team_schedule.effective_query.results.work_packages
                    .where(assigned_to_id: rows.map(&:id))
                    .includes(:status, :type, :priority)
    end

    # Filtering happens in SQL (via COALESCE to treat a single set date as
    # both the effective start and finish, matching #effective_start/
    # #effective_finish above) rather than loading every dated work package
    # for these assignees into Ruby — the Phase 13 performance target is 500
    # work packages intersecting a 4-week range out of a potentially much
    # larger per-project total.
    def scheduled_work_packages
      base_scope
        .where("start_date IS NOT NULL OR due_date IS NOT NULL")
        .where(
          "COALESCE(start_date, due_date) <= ? AND COALESCE(due_date, start_date) >= ?",
          visible_range.range_end, visible_range.range_start
        )
    end

    def unscheduled_by_row
      @unscheduled_by_row ||= base_scope.where(start_date: nil, due_date: nil)
                                        .group(:assigned_to_id).count
    end
  end
end
