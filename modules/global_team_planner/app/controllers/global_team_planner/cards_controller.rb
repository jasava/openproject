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

# Handles drag (reschedule / reassign) and resize updates for a single card.
#
# Every change — horizontal move, vertical move, resize, or a combination —
# goes through the exact same path a human editing the work package's date
# picker would use: WorkPackages::UpdateService, which runs
# WorkPackages::UpdateContract (the same contract the standard API/UI update
# path uses). This controller performs no authorization or validation of its
# own beyond loading the work package through its visible scope — "never use
# planner access as a substitute for work-package permissions" (see
# feature/04_team_planner_rework.md, "Dragging and resizing") is satisfied
# structurally, not by duplicating checks here:
# - Edit permission in the work package's own project is enforced by
#   WorkPackages::UpdateContract.
# - Target-assignee validity in that same project is enforced by the same
#   contract's `assigned_to` attribute validation
#   (Principal.possible_assignee(work_package), see
#   WorkPackages::BaseContract#assignable_assignees) — it is impossible for
#   this controller to accidentally assign a work package to a user who is
#   not assignable in its project.
# - The work package's project itself is never touched — no `project_id` is
#   among `card_params` below, so moving a work package to another project
#   (explicitly out of scope for the MVP) simply cannot happen through this
#   endpoint.
#
# The response always re-renders the card from a freshly reloaded work
# package, whether the update succeeded or failed. On failure this is what
# makes the card visually snap back to its true (unchanged) position — there
# is no separate client-side rollback code path to keep in sync.
#
# Deliberately keyed only by `:work_package_id` — no view/schedule id in the
# route at all, unlike the old project-scoped nested route
# (`card_project_team_schedule_path`); see
# feature/04_team_planner_rework.md, "Route structure". The originating grid
# still tells us *which* GlobalTeamPlannerView it was rendered from via an
# optional `view_id` body parameter (mirroring how `anchor`/`mode` are
# already sent as body params rather than URL segments by
# card.controller.ts) — purely so the re-rendered card can link back to the
# right split-view/base route and land in the same row order the visible
# grid used. This is never an authorization signal: a forged or
# no-longer-visible `view_id` only narrows what the *response* looks like,
# never what the work package update itself is allowed to do.
module ::GlobalTeamPlanner
  class CardsController < ::ApplicationController
    include OpTurbo::ComponentStream

    no_authorization_required! :update

    before_action :require_login
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

    def view
      @view ||= if params[:view_id].present?
                  GlobalTeamPlannerView.visible(current_user).find(params.expect(:view_id))
                else
                  GlobalTeamPlannerView.new(principal: current_user)
                end
    end

    def card_component
      grid = GlobalTeamPlanner::GridComponent.new(view:, current_user:, params:)
      row_number = grid.row_number_for(@work_package)

      GlobalTeamPlanner::CardComponent.new(
        work_package: @work_package,
        view:,
        grid_style: row_number && grid.card_style(@work_package, row_number)
      )
    end

    def find_work_package
      @work_package = WorkPackage.visible(current_user).find(params.expect(:work_package_id))
    end

    def card_params
      params.permit(:start_date, :due_date, :assigned_to_id, :lock_version).to_h.compact
    end
  end
end
