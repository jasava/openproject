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

FactoryBot.define do
  factory :global_team_planner_view, class: "GlobalTeamPlannerView" do
    sequence(:name) { |n| "Team schedule #{n}" }
    principal factory: :user
    public { false }
    project_scope_mode { "all_visible" }

    # A view created through the real create flow always has a query (see
    # GlobalTeamPlannerViews::SetAttributesService) — build one by default so
    # specs exercise the same `effective_query.results` SQL path production
    # traffic does, matching the equivalent guard in the old
    # team_schedule_factory.
    after(:build) do |view|
      next if view.query

      query = view.build_default_query
      query.name = "Query for #{view.name}"
      view.query = query
    end

    trait :without_query do
      after(:build) { |view| view.query = nil }
    end

    trait :selected_projects do
      project_scope_mode { "selected" }
    end
  end
end
