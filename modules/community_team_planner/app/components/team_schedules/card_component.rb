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

module TeamSchedules
  class CardComponent < ApplicationComponent
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    def initialize(work_package:, team_schedule:, project:, grid_style: nil, editable: true)
      super

      @work_package = work_package
      @team_schedule = team_schedule
      @project = project
      @grid_style = grid_style
      @editable = editable
    end

    def wrapper_key
      "team-schedule-card-#{@work_package.id}"
    end

    delegate :start_date, to: :@work_package

    delegate :due_date, to: :@work_package

    # Only leaf work packages and manually-scheduled ones accept a direct
    # date write (see WorkPackages::BaseContract#leaf_or_manually_scheduled?)
    # — a parent whose dates are derived from its children cannot be dragged
    # or resized directly, matching how the work-package details view treats
    # those fields as read-only for the same work package.
    def draggable?
      @editable && (@work_package.leaf? || @work_package.schedule_manually?) && editable_dates?
    end

    def editable_dates?
      WorkPackages::UpdateContract.update_allowed?(user: User.current, work_package: @work_package)
    end

    def milestone?
      start_date.present? && start_date == due_date
    end

    def status_name
      @work_package.status&.name
    end

    def accessible_label
      I18n.t("community_team_planner.card.aria_label",
             id: @work_package.id,
             subject: @work_package.subject,
             assignee: assignee_name,
             start_date: formatted_date(start_date),
             due_date: formatted_date(due_date),
             status: status_name)
    end

    def split_view_href
      # `tab` must be present, not just default-able: WorkPackages::SplitViewHelper
      # forwards `params[:tab]` verbatim into WorkPackages::Details::TabComponent,
      # which calls `.to_sym` on it unconditionally — a missing tab param becomes
      # `nil.to_sym` instead of falling back to the component's own `:overview`
      # default.
      helpers.project_team_schedule_path(
        @project, @team_schedule,
        work_package_split_view: 1,
        work_package_id: @work_package.id,
        tab: "overview"
      )
    end

    def card_url
      helpers.card_project_team_schedule_path(@project, @team_schedule, work_package_id: @work_package.id)
    end

    private

    def assignee_name
      @work_package.assigned_to&.name || I18n.t("community_team_planner.card.no_assignee")
    end

    def formatted_date(date)
      date ? helpers.format_date(date) : I18n.t("community_team_planner.grid.no_dates")
    end
  end
end
