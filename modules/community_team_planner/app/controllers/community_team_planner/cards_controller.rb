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

# Handles drag (reschedule / reassign) and resize updates for a single card.
#
# Every change — horizontal move, vertical move, resize, or a combination —
# goes through the exact same path a human editing the work package's date
# picker would use: WorkPackages::UpdateService, which runs
# WorkPackages::UpdateContract (the same contract the standard API/UI update
# path uses). This controller performs no authorization or validation of its
# own beyond loading the work package through its visible scope — the
# "Never use planner permission as a substitute for work-package permissions"
# requirement is satisfied structurally, not by duplicating checks here.
#
# The response always re-renders the card from a freshly reloaded work
# package, whether the update succeeded or failed. On failure this is what
# makes the card visually snap back to its true (unchanged) position — there
# is no separate client-side rollback code path to keep in sync.
module ::CommunityTeamPlanner
  class CardsController < BaseController
    include OpTurbo::ComponentStream

    before_action :find_project_by_project_id
    before_action :authorize
    before_action :find_team_schedule
    before_action :find_work_package

    def update
      call = WorkPackages::UpdateService
               .new(user: current_user, model: @work_package)
               .call(card_params)

      render_error_flash_message_via_turbo_stream(message: call.errors.full_messages.to_sentence) unless call.success?

      @work_package.reload
      replace_via_turbo_stream(component: card_component)
      respond_with_turbo_streams(status: call.success? ? :ok : :unprocessable_entity)
    end

    private

    def card_component
      grid = TeamSchedules::GridComponent.new(team_schedule: @team_schedule, project: @project, params:)
      row_index = grid.rows.index { |principal| principal.id == @work_package.assigned_to_id }
      style = row_index && grid.card_style(@work_package, grid.row_number(row_index))

      TeamSchedules::CardComponent.new(
        work_package: @work_package,
        team_schedule: @team_schedule,
        project: @project,
        grid_style: style
      )
    end

    def find_team_schedule
      @team_schedule = TeamSchedule.visible(current_user).where(project: @project).find(params.expect(:id))
    end

    def find_work_package
      @work_package = WorkPackage.visible(current_user).find(params.expect(:work_package_id))
    end

    def card_params
      params.permit(:start_date, :due_date, :assigned_to_id, :lock_version).to_h.compact
    end
  end
end
