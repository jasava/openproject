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
  class TableComponent < ::OpPrimer::BorderBoxTableComponent
    options :current_project

    columns :name, :members, :updated_at

    mobile_columns :name

    main_column :name

    def sortable?
      false
    end

    def paginated?
      false
    end

    def has_actions?
      true
    end

    def mobile_title
      I18n.t("community_team_planner.label_plural")
    end

    def headers
      [
        [:name, { caption: TeamSchedule.human_attribute_name(:name) }],
        [:members, { caption: I18n.t(:label_member_plural) }],
        [:updated_at, { caption: TeamSchedule.human_attribute_name(:updated_at) }]
      ]
    end

    def columns
      headers.map(&:first)
    end

    def blank_title
      I18n.t("community_team_planner.index.empty_state.title")
    end

    def blank_description
      I18n.t("community_team_planner.index.empty_state.description")
    end
  end
end
