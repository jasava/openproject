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
  class SetAttributesService < ::BaseServices::SetAttributes
    private

    def set_default_attributes(_params)
      model.change_by_system do
        model.principal ||= user
        model.query ||= default_query
      end
    end

    def default_query
      query = model.build_default_query
      # `queries.name` is NOT NULL and Query.new_default does not set one
      # (confirmed by reading app/models/query.rb) — every other caller of
      # new_default in this codebase supplies its own name afterwards.
      query.name = I18n.t("community_team_planner.query_name", name: model.name.presence || "Team Schedule")
      query
    end
  end
end
