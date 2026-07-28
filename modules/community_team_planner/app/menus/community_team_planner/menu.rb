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

module CommunityTeamPlanner
  class Menu < Submenu
    def initialize(project: nil, params: nil)
      # TeamSchedule does not use the classic Views STI, so view_type is
      # irrelevant here; pass a placeholder to satisfy the parent class.
      super(view_type: "team_schedule", params: params || {}, project:)
    end

    def menu_items
      [
        menu_group(header: I18n.t("community_team_planner.sidebar.public"), children: public_schedules),
        menu_group(header: I18n.t("community_team_planner.sidebar.private"), children: private_schedules)
      ]
    end

    def public_schedules
      base_scope.public_views.map { |schedule| schedule_item(schedule) }
    end

    def private_schedules
      base_scope.private_views(User.current).map { |schedule| schedule_item(schedule) }
    end

    private

    def base_scope
      TeamSchedule
        .visible(User.current)
        .where(project:)
        .with_favorited_by_user(User.current)
        .order(favorited: :desc, name: :asc)
    end

    def schedule_item(schedule)
      OpenProject::Menu::MenuItem.new(
        title: schedule.name,
        href: project_team_schedule_path(project, schedule),
        icon: nil,
        count: nil,
        selected: schedule.id.to_s == params[:id].to_s,
        favorited: schedule.favorited,
        show_enterprise_icon: false
      )
    end
  end
end
