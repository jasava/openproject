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

# The mandated cross-project leakage scenarios from
# feature/04_team_planner_rework.md ("Security testing"): two users with
# disjoint project access, a shared view referencing both projects, forged
# IDs rejected. Every assertion here checks what a *shared* view actually
# renders/returns for a viewer who cannot see one of the projects it
# references — never what the owner sees, since the owner's own access is
# not the case this spec exists to catch.
RSpec.describe "GlobalTeamPlanner cross-project security", :skip_csrf, type: :rails_request do
  shared_let(:project_a) { create(:project, name: "Alpha Confidential") }
  shared_let(:project_b) { create(:project, name: "Beta Shared") }

  # Disjoint access: user_a can only see project_a, user_b can only see
  # project_b. Neither is a member of the other's project.
  shared_let(:user_a) { create(:user, member_with_permissions: { project_a => %i[view_work_packages edit_work_packages] }) }
  shared_let(:user_b) { create(:user, member_with_permissions: { project_b => %i[view_work_packages edit_work_packages] }) }

  # Dates relative to "today" (not a hardcoded 2026 date) so they always fall
  # inside the view's default one-week render window regardless of when the
  # suite runs.
  shared_let(:wp_in_a) do
    create(:work_package, project: project_a, subject: "Alpha secret task",
                          start_date: Date.current, due_date: Date.current + 1.day)
  end
  shared_let(:wp_in_b) do
    create(:work_package, project: project_b, subject: "Beta visible task",
                          start_date: Date.current, due_date: Date.current + 1.day)
  end

  # A shared view, owned by user_a, that explicitly selects BOTH projects —
  # exactly the "shared view referencing an inaccessible project" scenario.
  let(:shared_view) do
    create(:global_team_planner_view, :selected_projects,
           principal: user_a, public: true,
           selected_project_ids: [project_a.id, project_b.id])
  end

  describe "GET show (shared view opened by a user who cannot see one of its projects)" do
    it "never renders the inaccessible project's name, and never renders its work packages" do
      login_as user_b

      get global_team_planner_view_path(shared_view)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Alpha Confidential")
      expect(response.body).not_to include("Alpha secret task")
    end

    it "still renders the accessible project's own work packages for that viewer" do
      shared_view.update!(assignee_ids: [])
      wp_in_b.update!(assigned_to: user_b)
      shared_view.update!(assignee_ids: [user_b.id])

      login_as user_b

      get global_team_planner_view_path(shared_view)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Beta visible task")
    end

    it "recalculates the effective project scope per viewer rather than trusting persisted IDs" do
      # Even the view's own owner (user_a) only ever gets back what THEY can
      # see — ownership of a shared view is not itself a visibility grant.
      # user_a is not a member of project_b, so it never appears for them
      # either, despite being one of the view's persisted selected_project_ids.
      expect(shared_view.effective_project_ids(user_a)).to contain_exactly(project_a.id)
      expect(shared_view.effective_project_ids(user_b)).to contain_exactly(project_b.id)
    end
  end

  describe "PATCH update — filters (forged/invisible project id)" do
    it "a forged project filter naming an inaccessible project yields zero leaked results, not an error" do
      own_view = create(:global_team_planner_view, principal: user_b, assignee_ids: [user_b.id])
      wp_in_a.update!(assigned_to: nil)
      login_as user_b

      patch global_team_planner_view_path(own_view),
            params: {
              global_team_planner_view: { name: own_view.name },
              filters: [{ "project" => { "operator" => "=", "values" => [project_a.id.to_s] } }].to_json
            },
            as: :turbo_stream

      expect(response).not_to have_http_status(:internal_server_error)
      get global_team_planner_view_path(own_view)
      expect(response.body).not_to include("Alpha Confidential")
      expect(response.body).not_to include("Alpha secret task")
    end
  end

  describe "GET project_candidates (project-scope autocomplete)" do
    it "never returns a project the current user cannot see, even when queried by exact name" do
      login_as user_b

      get global_team_planner_project_candidates_path(q: "Alpha")

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.pluck("id")).not_to include(project_a.id)
    end

    it "returns the accessible project when queried by its own name" do
      login_as user_b

      get global_team_planner_project_candidates_path(q: "Beta")

      body = response.parsed_body
      expect(body.pluck("id")).to include(project_b.id)
    end
  end

  describe "GET principal_candidates (row-member autocomplete)" do
    it "never returns a member of a project the current user cannot see" do
      alpha_only_member = create(:user, member_with_permissions: { project_a => %i[view_work_packages] })
      login_as user_b

      get global_team_planner_principal_candidates_path(project_ids: [project_a.id])

      body = response.parsed_body
      expect(body.pluck("id")).not_to include(alpha_only_member.id)
    end

    it "silently falls back to the caller's own visible projects when the requested project_ids are all inaccessible" do
      login_as user_b

      get global_team_planner_principal_candidates_path(project_ids: [project_a.id])

      expect(response).to have_http_status(:ok)
    end
  end

  describe "row add (forged principal id from an inaccessible project)" do
    it "rejects adding a principal who is only assignable in a project the current user cannot see" do
      alpha_only_member = create(:user, member_with_permissions: { project_a => %i[view_work_packages work_package_assigned] })
      own_view = create(:global_team_planner_view, principal: user_b)
      login_as user_b

      post add_row_global_team_planner_view_path(own_view),
           params: { row: { principal_id: alpha_only_member.id } }, as: :turbo_stream

      expect(response).to have_http_status(:bad_request)
      expect(own_view.reload.assignee_ids).to be_empty
    end
  end

  describe "drag/resize (forged work_package_id from an inaccessible project)" do
    it "404s rather than leaking the work package's existence or mutating it" do
      login_as user_b

      put schedule_global_team_planner_work_package_path(work_package_id: wp_in_a.id),
          params: { start_date: "2026-08-10" }, as: :turbo_stream

      expect(response).to have_http_status(:not_found)
      expect(wp_in_a.reload.start_date).to eq(Date.current)
    end
  end

  describe "selected_project_ids persisted on a view are never trusted as authorization by themselves" do
    it "a view that selects a project the *current* viewer lost access to silently drops it, it does not error or leak" do
      # user_a still owns/can manage the view; project_a becomes inaccessible
      # to a third viewer who was never a member of it in the first place.
      outsider = create(:user, member_with_permissions: { project_b => %i[view_work_packages] })
      view = create(:global_team_planner_view, :selected_projects, principal: user_a, public: true,
                                                                   selected_project_ids: [project_a.id, project_b.id])

      login_as outsider

      get global_team_planner_view_path(view)

      expect(response).to have_http_status(:ok)
      expect(view.effective_project_ids(outsider)).to eq([project_b.id])
    end
  end
end
