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

RSpec.describe "TeamSchedules requests", :skip_csrf, type: :rails_request do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[community_team_planner work_package_tracking])
  end
  shared_let(:manager) do
    create(:user,
           member_with_permissions: { project => %i[view_community_team_planner manage_community_team_planner
                                                    view_work_packages] })
  end
  shared_let(:viewer) do
    create(:user, member_with_permissions: { project => %i[view_community_team_planner view_work_packages] })
  end
  shared_let(:outsider) { create(:user) }

  describe "GET index" do
    it "is reachable by a project member with view_community_team_planner" do
      login_as viewer

      get project_team_schedules_path(project)

      expect(response).to have_http_status(:ok)
    end

    it "404s for a user without project access" do
      login_as outsider

      get project_team_schedules_path(project)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET show" do
    let(:schedule) { create(:team_schedule, project:, principal: manager, public: true) }

    it "renders the schedule grid" do
      login_as viewer

      get project_team_schedule_path(project, schedule)

      expect(response).to have_http_status(:ok)
    end

    context "when the schedule is private and belongs to someone else" do
      let(:other_owner) do
        create(:user, member_with_permissions: { project => %i[view_community_team_planner view_work_packages] })
      end
      let(:private_schedule) { create(:team_schedule, project:, principal: other_owner, public: false) }

      it "is not findable by a different user" do
        login_as viewer

        get project_team_schedule_path(project, private_schedule)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST create" do
    subject(:perform) do
      post project_team_schedules_path(project),
           params: { team_schedule: { name: "Sprint 12" } },
           as: :turbo_stream
    end

    it "is denied for a user without manage_community_team_planner" do
      login_as viewer

      expect { perform }.not_to change(TeamSchedule, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "creates a schedule owned by the current user, with a default query" do
      login_as manager

      expect { perform }.to change(TeamSchedule, :count).by(1)

      schedule = TeamSchedule.last
      expect(schedule.name).to eq("Sprint 12")
      expect(schedule.principal).to eq(manager)
      expect(schedule.public?).to be(false)
      expect(schedule.query).to be_a(Query)
    end

    it "does not persist a schedule with a blank name" do
      login_as manager

      expect do
        post project_team_schedules_path(project), params: { team_schedule: { name: "" } }, as: :turbo_stream
      end.not_to change(TeamSchedule, :count)
    end
  end

  describe "PATCH update / visibility" do
    let(:schedule) { create(:team_schedule, project:, principal: manager, public: false) }

    it "lets the owner rename their private schedule" do
      login_as manager

      patch project_team_schedule_path(project, schedule), params: { team_schedule: { name: "Renamed" } }

      expect(schedule.reload.name).to eq("Renamed")
    end

    it "does not let another manage-permitted user rename someone else's private schedule" do
      other_manager = create(:user,
                             member_with_permissions: { project => %i[view_community_team_planner
                                                                      manage_community_team_planner
                                                                      view_work_packages] })
      login_as other_manager

      patch project_team_schedule_path(project, schedule), params: { team_schedule: { name: "Hijacked" } }

      expect(response).to have_http_status(:not_found)
      expect(schedule.reload.name).not_to eq("Hijacked")
    end
  end

  describe "DELETE destroy" do
    let(:schedule) { create(:team_schedule, project:, principal: manager) }

    it "is denied for a viewer" do
      login_as viewer
      schedule

      expect do
        delete project_team_schedule_path(project, schedule)
      end.not_to change(TeamSchedule, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "deletes the schedule for its owner" do
      login_as manager
      schedule

      expect { delete project_team_schedule_path(project, schedule) }.to change(TeamSchedule, :count).by(-1)
    end
  end

  describe "row management" do
    let(:schedule) { create(:team_schedule, project:, principal: manager) }
    let(:row_member) do
      create(:user, member_with_permissions: { project => %i[view_community_team_planner view_work_packages] })
    end

    it "adds a project member as a row" do
      login_as manager

      post add_row_project_team_schedule_path(project, schedule),
           params: { row: { principal_id: row_member.id } }, as: :turbo_stream

      expect(schedule.reload.assignee_ids).to eq([row_member.id])
    end

    it "rejects adding a principal who is not a member of the project" do
      login_as manager
      stranger = create(:user)

      post add_row_project_team_schedule_path(project, schedule),
           params: { row: { principal_id: stranger.id } }, as: :turbo_stream

      expect(schedule.reload.assignee_ids).to be_empty
      expect(response).to have_http_status(:bad_request)
    end

    it "removing a row never touches the underlying work package assignment" do
      login_as manager
      work_package = create(:work_package, project:, assigned_to: row_member)
      schedule.update!(assignee_ids: [row_member.id])

      delete remove_row_project_team_schedule_path(project, schedule, principal_id: row_member.id),
             as: :turbo_stream

      expect(schedule.reload.assignee_ids).to be_empty
      expect(work_package.reload.assigned_to).to eq(row_member)
    end

    it "is denied for a viewer" do
      login_as viewer

      post add_row_project_team_schedule_path(project, schedule),
           params: { row: { principal_id: row_member.id } }, as: :turbo_stream

      expect(schedule.reload.assignee_ids).to be_empty
      expect(response).to have_http_status(:forbidden)
    end
  end
end
