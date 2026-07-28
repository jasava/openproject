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

# Deliberately no `scope "projects/:project_id"` anywhere in this file — Team
# Schedule is a global feature (see feature/04_team_planner_rework.md,
# "Critical correction"). Every route below works without a project context.
Rails.application.routes.draw do
  get "team_schedule" => "global_team_planner/global_team_planner#show", as: "global_team_planner"

  scope "team_schedule", controller: "global_team_planner/global_team_planner" do
    get "project_candidates", action: :project_candidates, as: "global_team_planner_project_candidates"
    get "principal_candidates", action: :principal_candidates, as: "global_team_planner_principal_candidates"

    resources :views, only: %i[index new create show edit update destroy], as: "global_team_planner_views",
                      controller: "global_team_planner/global_team_planner" do
      member do
        post :toggle_public
        get "rows/new", action: :new_row, as: :new_row
        post :add_row
        delete "rows/:principal_id", action: :remove_row, as: :remove_row
        put :reorder_rows
      end
    end
  end

  put "team_schedule/work_packages/:work_package_id/schedule" => "global_team_planner/cards#update",
      as: "schedule_global_team_planner_work_package"
end
