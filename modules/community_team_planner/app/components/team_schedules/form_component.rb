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

module TeamSchedules
  class FormComponent < ApplicationComponent
    include ApplicationHelper
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    def initialize(team_schedule:, project:, url:, method:, form_id:, base_errors: nil, show_filters: false)
      super

      @team_schedule = team_schedule
      @project = project
      @url = url
      @method = method
      @form_id = form_id
      @base_errors = base_errors
      @show_filters = show_filters
    end

    def show_filters?
      @show_filters && @team_schedule.effective_query.present?
    end

    private

    def can_manage_public?
      User.current.allowed_in_project?(:manage_community_team_planner, @project)
    end
  end
end
