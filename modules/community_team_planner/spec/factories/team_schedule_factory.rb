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

FactoryBot.define do
  factory :team_schedule, class: "TeamSchedule" do
    sequence(:name) { |n| "Team schedule #{n}" }
    project
    principal factory: :user
    public { false }

    # A schedule created through the real create flow always has a query
    # (see TeamSchedules::SetAttributesService) — build one by default so
    # specs exercise the same `effective_query.results` SQL path production
    # traffic does. Without this, `effective_query` is nil and `GridComponent`
    # silently takes its "no query" short-circuit branch instead, which is
    # exactly how a real GROUP BY/ORDER BY conflict against the query's
    # default sort criteria slipped past every existing spec.
    after(:build) do |schedule|
      next if schedule.query

      query = schedule.build_default_query
      query.name = "Query for #{schedule.name}"
      schedule.query = query
    end

    trait :without_query do
      after(:build) { |schedule| schedule.query = nil }
    end
  end
end
