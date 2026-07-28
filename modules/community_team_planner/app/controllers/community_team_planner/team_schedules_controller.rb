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

module ::CommunityTeamPlanner
  class TeamSchedulesController < BaseController
    include OpTurbo::ComponentStream

    menu_item :community_team_planner

    before_action :find_project_by_project_id
    before_action :authorize
    before_action :find_team_schedule, only: %i[show edit update destroy toggle_public
                                                new_row add_row remove_row reorder_rows]
    before_action :authorize_manage, only: %i[edit update destroy toggle_public
                                              new_row add_row remove_row reorder_rows]
    before_action :build_team_schedule, only: %i[new create]

    def index
      @team_schedules = TeamSchedule
                          .visible(current_user)
                          .where(project: @project)
                          .order(:name)
    end

    def show
      @grid = TeamSchedules::GridComponent.new(team_schedule: @team_schedule, project: @project, params:)
    end

    def new
      respond_with_dialog TeamSchedules::NewDialogComponent.new(team_schedule: @team_schedule, project: @project)
    end

    def edit
      respond_with_dialog TeamSchedules::EditDialogComponent.new(team_schedule: @team_schedule, project: @project)
    end

    def create
      call = TeamSchedules::CreateService
               .new(user: current_user, model: @team_schedule)
               .call(create_params)

      if call.success?
        render turbo_stream: turbo_stream.redirect_to(project_team_schedule_path(@project, call.result))
      else
        render_create_failure(call)
      end
    end

    def update
      @team_schedule.apply_filters(params[:filters]) if params[:filters].present?

      call = update_service_call

      if call.success?
        flash[:notice] = I18n.t(:notice_successful_update)
        redirect_to project_team_schedule_path(@project, @team_schedule)
      else
        render_update_failure(call)
      end
    end

    def destroy
      TeamSchedules::DeleteService
        .new(user: current_user, model: @team_schedule)
        .call
        .on_success { flash[:notice] = I18n.t(:notice_successful_delete) }
        .on_failure { |call| flash[:error] = call.message }

      redirect_to project_team_schedules_path(@project), status: :see_other
    end

    def toggle_public
      call = TeamSchedules::UpdateService
               .new(user: current_user, model: @team_schedule)
               .call(public: !@team_schedule.public?)

      flash[call.success? ? :notice : :error] = call.success? ? I18n.t(:notice_successful_update) : call.message

      redirect_back_or_to(project_team_schedule_path(@project, @team_schedule), status: :see_other)
    end

    def new_row
      respond_with_dialog TeamSchedules::AddRowDialogComponent.new(team_schedule: @team_schedule, project: @project)
    end

    def add_row
      return render_400(message: I18n.t(:notice_file_not_found)) if new_row_principal_id.blank?
      return render_400 unless Principal.in_project(@project).exists?(id: new_row_principal_id)

      @team_schedule.add_row(new_row_principal_id)
      call = update_assignee_ids

      close_dialog_via_turbo_stream("##{TeamSchedules::AddRowDialogComponent::DIALOG_ID}") if call.success?
      respond_to_row_change(call, success_message: I18n.t("community_team_planner.flash.row_added"))
    end

    def remove_row
      @team_schedule.remove_row(params.expect(:principal_id))

      respond_to_row_change(update_assignee_ids, success_message: I18n.t("community_team_planner.flash.row_removed"))
    end

    def reorder_rows
      @team_schedule.reorder_rows(Array(params[:assignee_ids]))

      respond_to_row_change(update_assignee_ids, success_message: nil)
    end

    private

    def new_row_principal_id
      params.expect(row: [:principal_id])[:principal_id]
    end

    def update_assignee_ids
      TeamSchedules::UpdateService
        .new(user: current_user, model: @team_schedule)
        .call(assignee_ids: @team_schedule.assignee_ids)
    end

    def respond_to_row_change(call, success_message:)
      if call.success?
        flash.now[:notice] = success_message if success_message
        replace_via_turbo_stream(component: TeamSchedules::GridComponent.new(team_schedule: @team_schedule,
                                                                             project: @project, params:))
        respond_with_turbo_streams
      else
        render_error_flash_message_via_turbo_stream(message: call.errors.full_messages.to_sentence)
        respond_with_turbo_streams(status: :unprocessable_entity)
      end
    end

    def render_create_failure(call)
      update_via_turbo_stream(
        component: TeamSchedules::FormComponent.new(
          team_schedule: call.result,
          project: @project,
          url: project_team_schedules_path(@project),
          method: :post,
          form_id: TeamSchedules::NewDialogComponent::FORM_ID,
          base_errors: call.errors[:base]
        ),
        status: :unprocessable_entity
      )
      respond_with_turbo_streams
    end

    def render_update_failure(call)
      update_via_turbo_stream(
        component: TeamSchedules::FormComponent.new(
          team_schedule: call.result,
          project: @project,
          url: project_team_schedule_path(@project, @team_schedule),
          method: :patch,
          form_id: TeamSchedules::EditDialogComponent::FORM_ID,
          base_errors: call.errors[:base],
          show_filters: true
        ),
        status: :unprocessable_entity
      )
      respond_with_turbo_streams
    end

    def find_team_schedule
      @team_schedule = TeamSchedule.visible(current_user).where(project: @project).find(params.expect(:id))
    end

    def build_team_schedule
      @team_schedule = TeamSchedule.new(project: @project, principal: current_user)
    end

    def authorize_manage
      deny_access unless @team_schedule.manageable?(current_user)
    end

    def create_params
      params.expect(team_schedule: %i[name public]).merge(project: @project)
    end

    def update_params
      params.expect(team_schedule: %i[name public])
    end

    def update_service_call
      TeamSchedules::UpdateService
        .new(user: current_user, model: @team_schedule)
        .call(update_params)
    end
  end
end
