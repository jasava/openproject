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

module GlobalTeamPlanner
  class FormComponent < ApplicationComponent
    include ApplicationHelper
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    def initialize(view:, current_user:, url:, method:, form_id:, base_errors: nil, show_filters: false)
      super

      @view = view
      @current_user = current_user
      @url = url
      @method = method
      @form_id = form_id
      @base_errors = base_errors
      @show_filters = show_filters
    end

    def show_filters?
      @show_filters && @view.effective_query.present?
    end

    private

    # Unlike the old project-scoped TeamSchedules::FormComponent, there is no
    # per-project "manage community team planner" permission to check here:
    # a global view has no single project whose permission could govern it.
    # Anyone rendering this form already passed the controller's entry gate
    # (require_view_access!) and, for edits, GlobalTeamPlannerView#manageable?
    # (owner-only, see the model) via authorize_manage — so the "public"
    # toggle is simply always offered to whoever reaches this form. See
    # feature/04_team_planner_rework.md and the model's #visible? comment.
    def can_manage_public?
      true
    end
  end
end
