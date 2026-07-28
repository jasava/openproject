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

require "spec_helper"

RSpec.describe TeamSchedule do
  describe "#visible?" do
    shared_let(:project) { create(:project, enabled_module_names: %w[community_team_planner]) }
    shared_let(:owner) { create(:user, member_with_permissions: { project => %i[view_community_team_planner] }) }
    shared_let(:permitted_other) do
      create(:user, member_with_permissions: { project => %i[view_community_team_planner] })
    end
    shared_let(:non_member) { create(:user) }

    let(:schedule) { create(:team_schedule, project:, principal: owner, public: schedule_public) }

    context "with a private schedule" do
      let(:schedule_public) { false }

      it "is visible to the owner" do
        expect(schedule.visible?(owner)).to be(true)
      end

      it "is not visible to another permitted user" do
        expect(schedule.visible?(permitted_other)).to be(false)
      end

      it "is not visible to a non-member" do
        expect(schedule.visible?(non_member)).to be(false)
      end
    end

    context "with a public schedule" do
      let(:schedule_public) { true }

      it "is visible to any permitted user" do
        expect(schedule.visible?(permitted_other)).to be(true)
      end

      it "is not visible to users without view_community_team_planner on the project" do
        expect(schedule.visible?(non_member)).to be(false)
      end
    end
  end

  describe "#manageable?" do
    shared_let(:project) { create(:project, enabled_module_names: %w[community_team_planner]) }
    shared_let(:owner) do
      create(:user, member_with_permissions: { project => %i[view_community_team_planner manage_community_team_planner] })
    end
    shared_let(:other_manager) do
      create(:user, member_with_permissions: { project => %i[view_community_team_planner manage_community_team_planner] })
    end
    shared_let(:viewer_only) do
      create(:user, member_with_permissions: { project => %i[view_community_team_planner] })
    end

    it "a private schedule is only manageable by its owner, even for other users with manage rights" do
      schedule = create(:team_schedule, project:, principal: owner, public: false)

      expect(schedule.manageable?(owner)).to be(true)
      expect(schedule.manageable?(other_manager)).to be(false)
    end

    it "a public schedule is manageable by any user with manage_community_team_planner" do
      schedule = create(:team_schedule, project:, principal: owner, public: true)

      expect(schedule.manageable?(other_manager)).to be(true)
    end

    it "is never manageable by a user without manage_community_team_planner" do
      schedule = create(:team_schedule, project:, principal: owner, public: true)

      expect(schedule.manageable?(viewer_only)).to be(false)
    end
  end

  describe "row management" do
    let(:schedule) { build(:team_schedule) }

    it "adds a row and preserves insertion order" do
      schedule.add_row(3)
      schedule.add_row(1)
      schedule.add_row(2)

      expect(schedule.assignee_ids).to eq([3, 1, 2])
    end

    it "does not add a duplicate row" do
      schedule.add_row(3)
      schedule.add_row(3)

      expect(schedule.assignee_ids).to eq([3])
    end

    it "removes a row without disturbing the order of the rest" do
      schedule.add_row(1)
      schedule.add_row(2)
      schedule.add_row(3)

      schedule.remove_row(2)

      expect(schedule.assignee_ids).to eq([1, 3])
    end

    it "removing a row that is not present is a no-op" do
      schedule.add_row(1)

      schedule.remove_row(999)

      expect(schedule.assignee_ids).to eq([1])
    end

    it "reorders rows, ignoring ids that are no longer present and appending any left out" do
      schedule.add_row(1)
      schedule.add_row(2)
      schedule.add_row(3)

      schedule.reorder_rows([3, 1, 999])

      expect(schedule.assignee_ids).to eq([3, 1, 2])
    end
  end

  describe "#apply_filters" do
    shared_let(:project) { create(:project) }
    shared_let(:owner) { create(:user) }
    let(:schedule) do
      create(:team_schedule, project:, principal: owner).tap do |s|
        query = s.build_default_query
        query.name = "Query for #{s.name}"
        s.update!(query:)
      end
    end
    let(:status) { create(:status) }

    it "replaces the effective query's filters with the given APIv3 filter payload" do
      filters_json = [{ "status" => { "operator" => "=", "values" => [status.id.to_s] } }].to_json

      schedule.apply_filters(filters_json)

      expect(schedule.query.filters.map(&:name)).to include(:status)
      filter = schedule.query.filters.find { |f| f.name == :status }
      expect(filter.values).to eq([status.id.to_s])
    end

    it "clears previously set filters not present in the new payload" do
      schedule.query.add_filter("status_id", "=", [status.id.to_s])

      schedule.apply_filters([].to_json)

      expect(schedule.query.filters.map(&:name)).not_to include(:status_id)
    end

    it "is a no-op when the schedule has no query" do
      schedule.query = nil

      expect { schedule.apply_filters([].to_json) }.not_to raise_error
    end
  end

  describe "validations" do
    it "is invalid with an unknown display_mode" do
      schedule = build(:team_schedule, display_mode: "eight_weeks")

      expect(schedule).not_to be_valid
      expect(schedule.errors.symbols_for(:display_mode)).to include(:inclusion)
    end

    TeamSchedule::DISPLAY_MODES.each do |mode|
      it "accepts the #{mode} display mode" do
        schedule = build(:team_schedule, display_mode: mode)

        expect(schedule).to be_valid
      end
    end

    it "is invalid with more assignees than the configured maximum" do
      schedule = build(:team_schedule, assignee_ids: (1..(TeamSchedule::MAX_ASSIGNEES + 1)).to_a)

      expect(schedule).not_to be_valid
      expect(schedule.errors.symbols_for(:assignee_ids)).to include(:too_many)
    end

    it "requires a project" do
      schedule = build(:team_schedule, project: nil)

      expect(schedule).not_to be_valid
      expect(schedule.errors.symbols_for(:project)).to include(:blank)
    end
  end
end
