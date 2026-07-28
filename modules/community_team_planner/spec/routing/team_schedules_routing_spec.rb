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

RSpec.describe "Team schedules routing" do
  it "routes to team_schedules#index" do
    expect(get("/projects/1/team_schedule"))
      .to route_to("community_team_planner/team_schedules#index", project_id: "1")
  end

  it "routes to team_schedules#new" do
    expect(get("/projects/1/team_schedule/new"))
      .to route_to("community_team_planner/team_schedules#new", project_id: "1")
  end

  it "routes to team_schedules#show" do
    expect(get("/projects/1/team_schedule/2"))
      .to route_to("community_team_planner/team_schedules#show", project_id: "1", id: "2")
  end

  it "routes to team_schedules#create" do
    expect(post("/projects/1/team_schedule"))
      .to route_to("community_team_planner/team_schedules#create", project_id: "1")
  end

  it "routes to team_schedules#destroy" do
    expect(delete("/projects/1/team_schedule/2"))
      .to route_to("community_team_planner/team_schedules#destroy", project_id: "1", id: "2")
  end

  it "routes to team_schedules#add_row" do
    expect(post("/projects/1/team_schedule/2/add_row"))
      .to route_to("community_team_planner/team_schedules#add_row", project_id: "1", id: "2")
  end

  it "routes to team_schedules#remove_row" do
    expect(delete("/projects/1/team_schedule/2/rows/3"))
      .to route_to("community_team_planner/team_schedules#remove_row", project_id: "1", id: "2", principal_id: "3")
  end

  it "routes to cards#update" do
    expect(put("/projects/1/team_schedule/2/cards/3"))
      .to route_to("community_team_planner/cards#update", project_id: "1", id: "2", work_package_id: "3")
  end

  it "does not use the Enterprise team_planner identifier anywhere in its own namespace" do
    expect(get("/projects/1/team_schedule")).not_to route_to("team_planner/team_planner#index", project_id: "1")
  end
end
