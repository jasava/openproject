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

require "spec_helper"
require "support/permission_specs"

RSpec.describe CommunityTeamPlanner::TeamSchedulesController, type: :controller do
  include PermissionSpecs

  check_permission_required_for("community_team_planner/team_schedules#index", :view_community_team_planner)
  check_permission_required_for("community_team_planner/team_schedules#show", :view_community_team_planner)

  check_permission_required_for("community_team_planner/team_schedules#new", :manage_community_team_planner)
  check_permission_required_for("community_team_planner/team_schedules#create", :manage_community_team_planner)
  check_permission_required_for("community_team_planner/team_schedules#edit", :manage_community_team_planner)
  check_permission_required_for("community_team_planner/team_schedules#update", :manage_community_team_planner)
  check_permission_required_for("community_team_planner/team_schedules#destroy", :manage_community_team_planner)
end
