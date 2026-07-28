# frozen_string_literal: true

#-- copyright
# OpenProject Global Team Planner
# Copyright (C) the OpenProject community
#
# This is an independently maintained, Community-edition-only module. It does
# not depend on, alter, or gate itself behind any OpenProject Enterprise
# licensing mechanism. See docs/global-team-planner/adr-001-independent-module.md.
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

module OpenProject::GlobalTeamPlanner
  class Engine < ::Rails::Engine
    engine_name :openproject_global_team_planner

    include OpenProject::Plugins::ActsAsOpEngine

    # Deliberately no `project_module` block: Team Schedule is not a
    # per-project feature that a project admin enables/disables — it is
    # reachable from the global navigation for any user who can view work
    # packages in at least one project (see GlobalTeamPlannerController's
    # `require_view_access!`), and it is not registered as a permission at
    # all — it reuses the existing `:view_work_packages` /
    # `:edit_work_packages` permissions, checked per-project by the standard
    # WorkPackages::UpdateService/UpdateContract for every mutation. See
    # docs/global-team-planner/permissions.md for the full rationale.
    register "openproject-global_team_planner",
             author_url: "https://community.openproject.org",
             bundled: true,
             settings: {} do
      menu :top_menu,
           :global_team_planner,
           { controller: "/global_team_planner/global_team_planner", action: :show },
           caption: :label_global_team_planner,
           context: :modules,
           after: :work_packages,
           icon: "op-team-planner",
           if: ->(_) {
             (User.current.logged? || !Setting.login_required?) &&
               User.current.allowed_in_any_work_package?(:view_work_packages)
           }
    end
  end
end
