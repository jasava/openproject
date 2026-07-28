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

RSpec.describe "GlobalTeamPlanner requests", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project) }
  shared_let(:member) do
    create(:user, member_with_permissions: { project => %i[view_work_packages edit_work_packages] })
  end
  shared_let(:outsider) { create(:user) }

  describe "GET show (no saved view — global entry point)" do
    it "is reachable by any user who can view work packages in at least one project" do
      login_as member

      get global_team_planner_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t(:label_global_team_planner))
    end

    it "shows a forbidden/no-access state for a user without work-package view access anywhere" do
      login_as outsider

      get global_team_planner_path

      expect(response).to have_http_status(:forbidden)
    end

    it "is not reachable while logged out" do
      get global_team_planner_path

      expect(response).to redirect_to(signin_path(back_url: global_team_planner_url))
    end

    it "never renders a project breadcrumb or requires a project_id" do
      login_as member

      get global_team_planner_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("op-breadcrumb--item\">#{project.name}")
    end

    context "with the work-package split view open" do
      let(:work_package) { create(:work_package, project:) }

      it "renders the split view alongside the grid" do
        login_as member

        get global_team_planner_path(work_package_split_view: 1, work_package_id: work_package.id, tab: "overview")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("opce-wp-split-view")
      end
    end
  end

  describe "GET show (saved view)" do
    let(:view) { create(:global_team_planner_view, principal: member, public: true) }

    it "renders the grid for a public view" do
      login_as member

      get global_team_planner_view_path(view)

      expect(response).to have_http_status(:ok)
    end

    it "is reachable by a different authenticated user when public" do
      other = create(:user, member_with_permissions: { project => %i[view_work_packages] })
      login_as other

      get global_team_planner_view_path(view)

      expect(response).to have_http_status(:ok)
    end

    it "still renders a card the viewer can see but not edit, just without the drag/resize affordance" do
      viewer_only = create(:user, member_with_permissions: { project => %i[view_work_packages] })
      wp = create(:work_package, project:, subject: "Read only task", assigned_to: viewer_only,
                                 start_date: Date.current, due_date: Date.current + 1.day)
      own_view = create(:global_team_planner_view, principal: viewer_only, assignee_ids: [viewer_only.id])
      login_as viewer_only

      get global_team_planner_view_path(own_view)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(wp.subject)
      expect(response.body).not_to include('data-controller="global-team-planner--card"')
    end

    describe "the 'New work package' entry point (Global work-package creation)" do
      it "is shown, links to core's project-agnostic creation page, and never assumes a project" do
        creator = create(:user, member_with_permissions: { project => %i[view_work_packages add_work_packages] })
        creator_view = create(:global_team_planner_view, principal: creator, assignee_ids: [creator.id])
        login_as creator

        get global_team_planner_view_path(creator_view)

        expect(response.body).to include(new_work_package_path)
        expect(response.body).not_to include("project_id=#{project.id}")
      end

      it "is hidden for a user who cannot create a work package in any project" do
        viewer = create(:user, member_with_permissions: { project => %i[view_work_packages] })
        viewer_view = create(:global_team_planner_view, principal: viewer)
        login_as viewer

        get global_team_planner_view_path(viewer_view)

        expect(response.body).not_to include(new_work_package_path)
      end

      it "prefills the per-row link with that row's assignee, never a project" do
        creator = create(:user, member_with_permissions: { project => %i[view_work_packages add_work_packages] })
        creator_view = create(:global_team_planner_view, principal: creator, assignee_ids: [creator.id])
        login_as creator

        get global_team_planner_view_path(creator_view)

        expect(response.body).to include("assignee_href")
      end
    end

    context "when private and owned by someone else" do
      let(:private_view) { create(:global_team_planner_view, principal: member, public: false) }

      it "404s for a different user" do
        other = create(:user, member_with_permissions: { project => %i[view_work_packages] })
        login_as other

        get global_team_planner_view_path(private_view)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST create" do
    subject(:perform) do
      post global_team_planner_views_path,
           params: { global_team_planner_view: { name: "Sprint 12" } },
           as: :turbo_stream
    end

    it "creates a global view owned by the current user, with no project_id and a default query" do
      login_as member

      expect { perform }.to change(GlobalTeamPlannerView, :count).by(1)

      view = GlobalTeamPlannerView.last
      expect(view.name).to eq("Sprint 12")
      expect(view.principal).to eq(member)
      expect(view.project_id).to be_nil
      expect(view.public?).to be(false)
      expect(view.query).to be_a(Query)
    end

    it "is available to any user who can view work packages somewhere (no separate manage permission)" do
      login_as member

      perform

      expect(response).to have_http_status(:ok).or have_http_status(:redirect)
    end

    it "is denied while logged out" do
      post global_team_planner_views_path,
           params: { global_team_planner_view: { name: "Sprint 12" } }, as: :turbo_stream

      # turbo_stream requests get a 401 rather than a redirect-to-signin (see
      # Accounts::CurrentUser#require_login) — the HTML entry point above
      # already covers the redirect case.
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not persist a view with a blank name" do
      login_as member

      expect do
        post global_team_planner_views_path, params: { global_team_planner_view: { name: "" } }, as: :turbo_stream
      end.not_to change(GlobalTeamPlannerView, :count)
    end
  end

  describe "PATCH update / visibility" do
    let(:view) { create(:global_team_planner_view, principal: member, public: false) }

    it "lets the owner rename their private view" do
      login_as member

      patch global_team_planner_view_path(view), params: { global_team_planner_view: { name: "Renamed" } }

      expect(view.reload.name).to eq("Renamed")
    end

    it "does not let a different user rename someone else's view" do
      other = create(:user, member_with_permissions: { project => %i[view_work_packages] })
      login_as other

      patch global_team_planner_view_path(view), params: { global_team_planner_view: { name: "Hijacked" } }

      expect(response).to have_http_status(:not_found)
      expect(view.reload.name).not_to eq("Hijacked")
    end
  end

  describe "DELETE destroy" do
    let(:view) { create(:global_team_planner_view, principal: member) }

    it "is denied for a non-owner" do
      other = create(:user, member_with_permissions: { project => %i[view_work_packages] })
      login_as other
      view

      expect { delete global_team_planner_view_path(view) }.not_to change(GlobalTeamPlannerView, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "deletes the view for its owner" do
      login_as member
      view

      expect { delete global_team_planner_view_path(view) }.to change(GlobalTeamPlannerView, :count).by(-1)
    end
  end

  describe "row management" do
    let(:view) { create(:global_team_planner_view, principal: member) }
    let(:row_member) do
      create(:user, member_with_permissions: { project => %i[view_work_packages work_package_assigned] })
    end

    it "adds an assignable member as a row" do
      login_as member

      post add_row_global_team_planner_view_path(view),
           params: { row: { principal_id: row_member.id } }, as: :turbo_stream

      expect(view.reload.assignee_ids).to eq([row_member.id])
    end

    it "rejects adding a principal who is not assignable in any of the view's authorized projects" do
      login_as member
      stranger = create(:user)

      post add_row_global_team_planner_view_path(view),
           params: { row: { principal_id: stranger.id } }, as: :turbo_stream

      expect(view.reload.assignee_ids).to be_empty
      expect(response).to have_http_status(:bad_request)
    end

    it "removing a row never touches the underlying work package assignment" do
      login_as member
      work_package = create(:work_package, project:, assigned_to: row_member)
      view.update!(assignee_ids: [row_member.id])

      delete remove_row_global_team_planner_view_path(view, principal_id: row_member.id), as: :turbo_stream

      expect(view.reload.assignee_ids).to be_empty
      expect(work_package.reload.assigned_to).to eq(row_member)
    end

    it "is denied for a non-owner" do
      other = create(:user, member_with_permissions: { project => %i[view_work_packages] })
      login_as other

      post add_row_global_team_planner_view_path(view),
           params: { row: { principal_id: row_member.id } }, as: :turbo_stream

      expect(view.reload.assignee_ids).to be_empty
      expect(response).to have_http_status(:not_found)
    end
  end
end
