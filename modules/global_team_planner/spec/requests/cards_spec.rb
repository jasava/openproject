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

require "spec_helper"

RSpec.describe "Cards requests", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project) }
  shared_let(:editor) do
    create(:user, member_with_permissions: { project => %i[view_work_packages edit_work_packages] })
  end
  shared_let(:viewer_only) do
    create(:user, member_with_permissions: { project => %i[view_work_packages] })
  end

  let(:work_package) do
    create(:work_package, project:, assigned_to: editor,
                          start_date: Date.new(2026, 8, 3), due_date: Date.new(2026, 8, 5))
  end

  subject(:perform) do
    put schedule_global_team_planner_work_package_path(work_package_id: work_package.id),
        params: { start_date: "2026-08-04", due_date: "2026-08-06" },
        as: :turbo_stream
  end

  describe "PUT update" do
    it "reschedules the work package through the standard update path, preserving duration" do
      login_as editor

      expect { perform }.to change { work_package.reload.start_date }.to(Date.new(2026, 8, 4))
      expect(work_package.reload.due_date).to eq(Date.new(2026, 8, 6))
      expect(response).to have_http_status(:ok)
    end

    it "rejects the update for a user without work-package edit rights, leaving dates unchanged" do
      login_as viewer_only

      expect { perform }.not_to(change { work_package.reload.start_date })
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "404s for a work package outside the current user's visible scope" do
      other_project = create(:project) # no membership for editor at all
      foreign_wp = create(:work_package, project: other_project)

      login_as editor
      put schedule_global_team_planner_work_package_path(work_package_id: foreign_wp.id),
          params: { start_date: "2026-08-04" }, as: :turbo_stream

      expect(response).to have_http_status(:not_found)
    end

    it "reassigns the work package's assignee when assigned_to_id is sent" do
      other_member = create(:user,
                            member_with_permissions: { project => %i[view_work_packages edit_work_packages
                                                                     work_package_assigned] })
      login_as editor

      put schedule_global_team_planner_work_package_path(work_package_id: work_package.id),
          params: { assigned_to_id: other_member.id }, as: :turbo_stream

      expect(work_package.reload.assigned_to).to eq(other_member)
    end

    it "rejects reassigning to a principal who is not assignable in the work package's own project" do
      stranger = create(:user) # no membership in `project` at all
      login_as editor

      put schedule_global_team_planner_work_package_path(work_package_id: work_package.id),
          params: { assigned_to_id: stranger.id }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_entity)
      expect(work_package.reload.assigned_to).to eq(editor)
    end

    it "ignores unpermitted params (mass-assignment protection), never moving the work package's project" do
      other_project = create(:project)
      login_as editor

      put schedule_global_team_planner_work_package_path(work_package_id: work_package.id),
          params: { start_date: "2026-08-04", project_id: other_project.id, type_id: 999_999 },
          as: :turbo_stream

      expect(response).not_to have_http_status(:internal_server_error)
      expect(work_package.reload.project_id).to eq(project.id)
    end

    it "is denied while logged out" do
      put schedule_global_team_planner_work_package_path(work_package_id: work_package.id),
          params: { start_date: "2026-08-04" }, as: :turbo_stream

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "cross-project authorization (a single drag endpoint serves cards from any project)" do
    it "lets an editor of project A reschedule a card from project A while a foreign project's card stays out of reach" do
      project_b = create(:project)
      wp_in_a = create(:work_package, project:, start_date: Date.new(2026, 8, 1), due_date: Date.new(2026, 8, 2))
      wp_in_b = create(:work_package, project: project_b, start_date: Date.new(2026, 8, 1), due_date: Date.new(2026, 8, 2))

      login_as editor

      put schedule_global_team_planner_work_package_path(work_package_id: wp_in_a.id),
          params: { start_date: "2026-08-05", due_date: "2026-08-06" }, as: :turbo_stream
      expect(wp_in_a.reload.start_date).to eq(Date.new(2026, 8, 5))

      put schedule_global_team_planner_work_package_path(work_package_id: wp_in_b.id),
          params: { start_date: "2026-08-05", due_date: "2026-08-06" }, as: :turbo_stream
      expect(response).to have_http_status(:not_found)
      expect(wp_in_b.reload.start_date).to eq(Date.new(2026, 8, 1))
    end
  end
end
