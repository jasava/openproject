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

Rails.application.routes.draw do
  scope "projects/:project_id", as: "project" do
    resources :team_schedules,
              path: "team_schedule",
              controller: "community_team_planner/team_schedules" do
      member do
        post :toggle_public
        get "rows/new", action: :new_row, as: :new_row
        post :add_row
        delete "rows/:principal_id", action: :remove_row, as: :remove_row
        put :reorder_rows

        put "cards/:work_package_id", controller: "community_team_planner/cards", action: :update, as: :card
      end

      collection do
        get "menu" => "community_team_planner/menus#show"
      end
    end
  end
end
