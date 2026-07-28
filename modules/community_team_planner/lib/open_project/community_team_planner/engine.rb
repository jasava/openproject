# frozen_string_literal: true

#-- copyright
# OpenProject Community Team Planner
# Copyright (C) the OpenProject community
#
# This is an independently maintained, Community-edition-only module. It does
# not depend on, alter, or gate itself behind any OpenProject Enterprise
# licensing mechanism. See docs/community-team-planner/adr-001-independent-module.md.
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

require "open_project/plugins"

module OpenProject::CommunityTeamPlanner
  class Engine < ::Rails::Engine
    engine_name :openproject_community_team_planner

    include OpenProject::Plugins::ActsAsOpEngine

    register "openproject-community_team_planner",
             author_url: "https://community.openproject.org",
             bundled: true,
             settings: {} do
      project_module :community_team_planner, dependencies: :work_package_tracking do
        # Gates opening the schedule index/show pages and reading saved schedules.
        # Card mutation (drag/resize/reassign) also lives behind this permission —
        # the *real* authorization for changing a work package's assignee/dates is
        # enforced by WorkPackages::UpdateContract (the same contract the standard
        # work-package update path uses), not by this module. This permission only
        # establishes that the user may be in the Team Schedule area at all; it is
        # never a substitute for work-package edit permissions.
        permission :view_community_team_planner,
                   {
                     "community_team_planner/team_schedules": %i[index show],
                     "community_team_planner/cards": %i[update],
                     "community_team_planner/menus": %i[show]
                   },
                   permissible_on: :project,
                   dependencies: %i[view_work_packages]

        # Gates schedule *configuration*: creating/renaming/saving/deleting a
        # schedule, changing its visibility, and adding/removing/reordering rows.
        # It never grants permission to change work-package data.
        permission :manage_community_team_planner,
                   {
                     "community_team_planner/team_schedules": %i[new create edit update destroy
                                                                 toggle_public new_row add_row remove_row
                                                                 reorder_rows]
                   },
                   permissible_on: :project,
                   dependencies: %i[view_community_team_planner]
      end

      menu :project_menu,
           :community_team_planner,
           { controller: "/community_team_planner/team_schedules", action: :index },
           caption: :label_community_team_planner,
           after: :work_packages,
           icon: "op-team-planner"

      menu :project_menu,
           :community_team_planner_menu,
           { controller: "/community_team_planner/team_schedules", action: :index },
           parent: :community_team_planner,
           partial: "community_team_planner/menus/menu",
           last: true,
           caption: :label_community_team_planner
    end
  end
end
