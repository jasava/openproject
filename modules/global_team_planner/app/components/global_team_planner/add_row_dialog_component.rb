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
  class AddRowDialogComponent < ApplicationComponent
    include ApplicationHelper
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    DIALOG_ID = "add-global-team-planner-row-dialog"
    FORM_ID = "add-global-team-planner-row-form"

    def initialize(view:, current_user:)
      super

      @view = view
      @current_user = current_user
    end

    private

    # The row picker must only ever offer principals assignable within the
    # view's *current, authorization-intersected* project scope — never "all
    # visible projects" (which is what
    # GlobalTeamPlannerController#principal_candidates falls back to when no
    # project_ids[] are supplied at all). See
    # feature/04_team_planner_rework.md, "Team rows".
    def candidate_project_ids
      @view.effective_project_ids(@current_user)
    end
  end
end
