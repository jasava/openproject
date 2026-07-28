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

# Global (non-project) Team Schedule. No `before_action :find_project`, no
# `:project_id` anywhere — see feature/04_team_planner_rework.md, "Critical
# correction".
#
# Access is intentionally NOT gated by a registered permission
# (`permissible_on: :project`/`:global`): it is gated by the same check the
# core global "Work packages" navigation entry already uses —
# `allowed_in_any_work_package?(:view_work_packages)` — so any user who can
# view a work package in at least one project can reach this page with zero
# admin configuration, matching the spec's explicit "preferred behavior".
# What each user actually *sees* inside the page (projects, rows, cards) is
# then bounded entirely by existing authorized scopes
# (`Project.visible`/`WorkPackage.visible`/`GlobalTeamPlanner::QueryBuilder`)
# — this controller never widens that.
module GlobalTeamPlanner
  class GlobalTeamPlannerController < ::ApplicationController
    include OpTurbo::ComponentStream
    include WorkPackages::WithSplitView
    include Layout

    layout "global"
    menu_item :global_team_planner

    no_authorization_required! :show, :index, :new, :create, :edit, :update, :destroy, :toggle_public,
                               :new_row, :add_row, :remove_row, :reorder_rows,
                               :project_candidates, :principal_candidates

    before_action :require_login
    before_action :require_view_access!
    before_action :find_view, only: %i[edit update destroy toggle_public new_row add_row remove_row reorder_rows]
    before_action :authorize_manage, only: %i[edit update destroy toggle_public new_row add_row remove_row reorder_rows]
    before_action :build_view, only: %i[new create]

    def index
      @views = GlobalTeamPlannerView.visible(current_user)
                                    .with_favorited_by_user(current_user)
                                    .order(favorited: :desc, name: :asc)
    end

    def show
      @view = params[:id].present? ? GlobalTeamPlannerView.visible(current_user).find(params.expect(:id)) : default_view
      @grid = GlobalTeamPlanner::GridComponent.new(view: @view, current_user:, params:)
    end

    def new
      respond_with_dialog GlobalTeamPlanner::NewDialogComponent.new(view: @view, current_user:)
    end

    def edit
      respond_with_dialog GlobalTeamPlanner::EditDialogComponent.new(view: @view, current_user:)
    end

    def create
      call = GlobalTeamPlannerViews::CreateService
               .new(user: current_user, model: @view)
               .call(create_params)

      if call.success?
        render turbo_stream: turbo_stream.redirect_to(global_team_planner_view_path(call.result))
      else
        render_create_failure(call)
      end
    end

    def update
      @view.apply_filters(params[:filters]) if params[:filters].present?

      call = GlobalTeamPlannerViews::UpdateService
               .new(user: current_user, model: @view)
               .call(update_params)

      call.success? ? redirect_to_updated_view : render_update_failure(call)
    end

    def destroy
      GlobalTeamPlannerViews::DeleteService
        .new(user: current_user, model: @view)
        .call
        .on_success { flash.now[:notice] = I18n.t(:notice_successful_delete) }
        .on_failure { |call| flash[:error] = call.message }

      redirect_to global_team_planner_views_path, status: :see_other
    end

    def toggle_public
      call = GlobalTeamPlannerViews::UpdateService
               .new(user: current_user, model: @view)
               .call(public: !@view.public?)

      flash[call.success? ? :notice : :error] = call.success? ? I18n.t(:notice_successful_update) : call.message

      redirect_back_or_to(global_team_planner_view_path(@view), status: :see_other)
    end

    def new_row
      respond_with_dialog GlobalTeamPlanner::AddRowDialogComponent.new(view: @view, current_user:)
    end

    def add_row
      candidate_id = new_row_principal_id
      return render_400(message: I18n.t(:notice_file_not_found)) if candidate_id.blank?
      return render_400 unless assignable_row_candidate?(candidate_id)

      @view.add_row(candidate_id)
      call = update_assignee_ids

      close_dialog_via_turbo_stream("##{GlobalTeamPlanner::AddRowDialogComponent::DIALOG_ID}") if call.success?
      respond_to_row_change(call, success_message: I18n.t("global_team_planner.flash.row_added"))
    end

    def remove_row
      @view.remove_row(params.expect(:principal_id))

      respond_to_row_change(update_assignee_ids, success_message: I18n.t("global_team_planner.flash.row_removed"))
    end

    def reorder_rows
      @view.reorder_rows(Array(params[:assignee_ids]))

      respond_to_row_change(update_assignee_ids, success_message: nil)
    end

    # GET /team_schedule/project_candidates?q=... — projects the current
    # user may add to a "selected" scope. Never returns a project the user
    # cannot see (Phase "Project scope selector": "avoid exposing
    # unauthorized project names through autocomplete"). Result-limited, not
    # paginated, matching the small "type to narrow down" UI it feeds.
    def project_candidates
      scope = Project.visible(current_user)
      if params[:q].present?
        scope = scope.where("LOWER(projects.name) LIKE :q OR LOWER(projects.identifier) LIKE :q",
                            q: "%#{params[:q].to_s.downcase}%")
      end

      render json: scope.order(:name).limit(50).pluck(:id, :identifier, :name).map { |id, identifier, name|
        { id:, identifier:, name: }
      }
    end

    # GET /team_schedule/principal_candidates?q=...&project_ids[]=...
    # Deduplicated members of the given (authorized-intersected) projects —
    # never "all OpenProject users" (Phase "Team rows": "do not query and
    # expose all OpenProject users by default").
    def principal_candidates
      render json: principal_candidates_scope.order(:lastname, :firstname).limit(50).map { |p| { id: p.id, name: p.name } }
    end

    current_menu_item :show do
      :global_team_planner
    end

    private

    def default_view
      GlobalTeamPlannerView.new(principal: current_user)
    end

    def require_view_access!
      return if current_user.allowed_in_any_work_package?(:view_work_packages)

      render "global_team_planner/global_team_planner/no_access", status: :forbidden, layout: "global"
    end

    def find_view
      @view = GlobalTeamPlannerView.visible(current_user).find(params.expect(:id))
    end

    def build_view
      @view = GlobalTeamPlannerView.new(principal: current_user)
    end

    def authorize_manage
      deny_access unless @view.manageable?(current_user)
    end

    def new_row_principal_id
      params.expect(row: [:principal_id])[:principal_id]
    end

    # Re-validates the candidate against the *live* authorized scope, not
    # just whatever the add-row dialog last rendered — mirrors
    # CardsController's own re-validation on drag (Phase "Assignability
    # across projects": never trust a client-supplied row membership claim).
    def assignable_row_candidate?(principal_id)
      candidate_projects = Project.visible(current_user).where(id: @view.effective_project_ids(current_user))
      Member.assignable.of_project(candidate_projects).exists?(user_id: principal_id)
    end

    def update_assignee_ids
      GlobalTeamPlannerViews::UpdateService
        .new(user: current_user, model: @view)
        .call(assignee_ids: @view.assignee_ids)
    end

    def redirect_to_updated_view
      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to global_team_planner_view_path(@view)
    end

    def principal_candidates_scope
      scope = Principal.where(id: Member.assignable.of_project(principal_candidate_projects).select(:user_id)).distinct
      params[:q].present? ? scope.like(params[:q]) : scope
    end

    def principal_candidate_projects
      requested = Project.visible(current_user).where(id: Array(params[:project_ids]))
      requested.none? ? Project.visible(current_user) : requested
    end

    def respond_to_row_change(call, success_message:)
      if call.success?
        flash.now[:notice] = success_message if success_message
        replace_via_turbo_stream(component: GlobalTeamPlanner::GridComponent.new(view: @view, current_user:, params:))
        respond_with_turbo_streams
      else
        render_error_flash_message_via_turbo_stream(message: call.errors.full_messages.to_sentence)
        respond_with_turbo_streams(status: :unprocessable_entity)
      end
    end

    def render_create_failure(call)
      update_via_turbo_stream(
        component: GlobalTeamPlanner::FormComponent.new(
          view: call.result,
          current_user:,
          url: global_team_planner_views_path,
          method: :post,
          form_id: GlobalTeamPlanner::NewDialogComponent::FORM_ID,
          base_errors: call.errors[:base]
        ),
        status: :unprocessable_entity
      )
      respond_with_turbo_streams
    end

    def render_update_failure(call)
      update_via_turbo_stream(
        component: GlobalTeamPlanner::FormComponent.new(
          view: call.result,
          current_user:,
          url: global_team_planner_view_path(@view),
          method: :patch,
          form_id: GlobalTeamPlanner::EditDialogComponent::FORM_ID,
          base_errors: call.errors[:base],
          show_filters: true
        ),
        status: :unprocessable_entity
      )
      respond_with_turbo_streams
    end

    # Where closing the work-package split view returns to. Preserves the
    # global planner state (view id, projects, filters, date range, display
    # mode) exactly like the project-scoped version did with its schedule —
    # see feature/04_team_planner_rework.md, "Split-view integration".
    def split_view_base_route
      extra_params = request.query_parameters.except("work_package_split_view", "work_package_id", "tab")
      if @view&.persisted?
        global_team_planner_view_path(@view, **extra_params.symbolize_keys)
      else
        global_team_planner_path(**extra_params.symbolize_keys)
      end
    end

    # `project_scope_mode`/`selected_project_ids` back
    # GlobalTeamPlannerViews::Forms::ProjectScopeForm's radio group + project
    # picker (rendered by GlobalTeamPlanner::FormComponent on both the
    # create and edit forms). Accepting `selected_project_ids` here is safe
    # precisely because it is never trusted as authorization by itself —
    # GlobalTeamPlannerView#effective_project_ids always re-intersects it
    # with `Project.visible(current_user)` at read time, and
    # BaseContract#selected_project_ids_must_be_integers/_within_limit still
    # validate the raw values before they are ever persisted.
    def create_params
      params.expect(
        global_team_planner_view: [:name, :public, :project_scope_mode, { selected_project_ids: [] }]
      ).merge(project: nil)
    end

    def update_params
      params.expect(
        global_team_planner_view: [:name, :public, :project_scope_mode, { selected_project_ids: [] }]
      )
    end
  end
end
