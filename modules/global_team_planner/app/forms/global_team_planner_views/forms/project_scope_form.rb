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

module GlobalTeamPlannerViews
  module Forms
    # Lets the view owner pick which projects Team Schedule aggregates
    # (GlobalTeamPlannerView#project_scope_mode / #selected_project_ids —
    # see feature/04_team_planner_rework.md, "Project scope selector"). This
    # is a plain ViewComponent (with its own template), NOT a declarative
    # Primer::Forms::Base field set like DetailsForm/PublicForm, because it
    # needs a custom Stimulus-driven project multi-picker (live search +
    # chips) that the Primer::Forms DSL has no field type for — see
    # frontend/src/stimulus/controllers/dynamic/global-team-planner/project-picker.controller.ts.
    #
    # Field names are written out by hand (`global_team_planner_view[...]`)
    # rather than going through a form builder, the same way
    # Filters::FilterFormComponent's own hidden input does — they only need
    # to match what GlobalTeamPlannerController#create_params/#update_params
    # read, not any particular builder API.
    #
    # The project picker only ever offers/resolves projects through
    # `Project.visible(current_user)` (see #selected_projects below and the
    # project-picker's `global_team_planner_project_candidates_path` fetch
    # target) — it never trusts `view.selected_project_ids` by itself, matching
    # the model's own #effective_project_ids.
    class ProjectScopeForm < ApplicationComponent
      include ApplicationHelper

      MODES = GlobalTeamPlannerView::PROJECT_SCOPE_MODES

      def initialize(view:, current_user:)
        super

        @view = view
        @current_user = current_user
      end

      private

      # Already-selected projects, re-resolved against the *current* user's
      # visible scope for display — never the persisted IDs alone (a
      # project the owner could see when they picked it, but that this
      # viewer can no longer see, must not leak its name/identifier here).
      def selected_projects
        return [] if @view.selected_project_ids.blank?

        Project.visible(@current_user)
               .where(id: @view.selected_project_ids)
               .order(:name)
               .pluck(:id, :identifier, :name)
      end
    end
  end
end
