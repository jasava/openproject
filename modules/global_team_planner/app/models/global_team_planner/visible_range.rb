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

# Computes the set of calendar days a Team Schedule grid should display for a
# given display mode and anchor date, using OpenProject's own working-day
# configuration (never assuming Saturday/Sunday are non-working, and never
# tied to any one project's calendar — working-day configuration in this
# codebase is instance-wide, not per-project; see
# WorkPackages::Shared::WorkingDays).
module GlobalTeamPlanner
  class VisibleRange
    DAYS_PER_MODE = {
      "one_week" => 7,
      "two_weeks" => 14,
      "four_weeks" => 28
    }.freeze

    attr_reader :display_mode, :anchor_date

    def initialize(display_mode:, anchor_date:, working_days: WorkPackages::Shared::WorkingDays.new)
      @display_mode = display_mode
      @anchor_date = anchor_date || Date.current
      @working_days = working_days
    end

    # All calendar days to render as columns, in order. For `work_week` this
    # is only the configured working days of the anchor's week (which may be
    # fewer or more than 5 days, and need not be Monday-Friday); for the
    # other modes it is every calendar day in the range, since non-working
    # days still need a (visually distinguished) column.
    def days
      @days ||= if work_week?
                  week_start.upto(week_start + 6).select { |d| @working_days.working?(d) }
                else
                  range_start.upto(range_end).to_a
                end
    end

    def range_start
      week_start
    end

    def range_end
      @range_end ||= work_week? ? week_start + 6 : week_start + (days_count - 1)
    end

    def previous_anchor
      anchor_date - jump_size
    end

    def next_anchor
      anchor_date + jump_size
    end

    private

    def work_week?
      display_mode == "work_week"
    end

    def days_count
      DAYS_PER_MODE.fetch(display_mode, 7)
    end

    def jump_size
      work_week? ? 7 : days_count
    end

    def week_start
      @week_start ||= anchor_date.beginning_of_week
    end
  end
end
