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

require "spec_helper"
require Rails.root.join("db/migrate/20260729090000_migrate_team_schedules_to_global_team_planner_views.rb")

# Raw table class, deliberately bypassing both the (now-unloadable, since
# Gemfile.modules no longer bundles community_team_planner) TeamSchedule
# model class and the new GlobalTeamPlannerView model's validations. A
# migration must be able to create/read/write rows exactly like this in
# production, where the application code that once matched an old STI type
# can be long gone — the migration itself uses the identical pattern (see
# db/migrate/20260729090000_..._views.rb). Defined at file scope (not inside
# the example group) so it is declared once, not re-opened/leaked per run.
class MigrateTeamSchedulesToGlobalTeamPlannerViewsSpecRawPersistedView < ApplicationRecord
  self.table_name = "persisted_views"
  self.inheritance_column = nil
end

RSpec.describe MigrateTeamSchedulesToGlobalTeamPlannerViews, type: :model do
  let(:project) { create(:project) }
  let(:user) { create(:user) }

  def raw_persisted_view_class
    MigrateTeamSchedulesToGlobalTeamPlannerViewsSpecRawPersistedView
  end

  def create_old_team_schedule(project_id:, options: {})
    raw_persisted_view_class.create!(
      type: "TeamSchedule",
      name: "Old schedule",
      project_id:,
      principal_id: user.id,
      public: false,
      options: { "display_mode" => "one_week", "assignee_ids" => [user.id] }.merge(options)
    )
  end

  def reload_raw(view)
    raw_persisted_view_class.find(view.id)
  end

  subject(:migrate_up) { ActiveRecord::Migration.suppress_messages { described_class.new.up } }

  context "when migrating up" do
    it "renames the STI type, nullifies project_id, and seeds selected_project_ids" do
      old = create_old_team_schedule(project_id: project.id)

      migrate_up
      old = reload_raw(old)

      expect(old.type).to eq("GlobalTeamPlannerView")
      expect(old.project_id).to be_nil
      expect(old.options["project_scope_mode"]).to eq("selected")
      expect(old.options["selected_project_ids"]).to eq([project.id])
      # Existing options (e.g. assignee_ids) are preserved, not clobbered.
      expect(old.options["assignee_ids"]).to eq([user.id])
    end

    it "does nothing to records that are not TeamSchedule (idempotent-safe for other PersistedView subtypes)" do
      other = PersistedView.create!(type: "PersistedView", name: "Unrelated", options: {})

      expect { migrate_up }.not_to(change { other.reload.attributes })
    end

    it "is a no-op when no TeamSchedule rows exist" do
      expect { migrate_up }.not_to change(PersistedView, :count)
    end
  end

  context "when migrating down" do
    subject(:migrate_down) { ActiveRecord::Migration.suppress_messages { described_class.new.down } }

    it "restores the STI type and project_id from the first selected project" do
      # Built via the same raw table class the migration itself uses (not
      # `GlobalTeamPlannerView.create!`), so the fixture's `options` values
      # are plain native JSON, matching what `down` itself writes for a row
      # migrated by `up` — see json_array's comment for why `down` must also
      # tolerate the JSON-string-in-jsonb shape a real app save produces,
      # which is exercised separately by the round-trip example below.
      migrated = raw_persisted_view_class.create!(
        type: "GlobalTeamPlannerView",
        name: "Migrated schedule",
        project_id: nil,
        principal_id: user.id,
        public: false,
        options: {
          "display_mode" => "one_week",
          "assignee_ids" => [user.id],
          "project_scope_mode" => "selected",
          "selected_project_ids" => [project.id]
        }
      )

      migrate_down
      migrated = reload_raw(migrated)

      expect(migrated.type).to eq("TeamSchedule")
      expect(migrated.project_id).to eq(project.id)
      expect(migrated.options).not_to have_key("project_scope_mode")
      expect(migrated.options).not_to have_key("selected_project_ids")
      expect(migrated.options["assignee_ids"]).to eq([user.id])
    end

    it "round-trips up then down back to the original state" do
      old = create_old_team_schedule(project_id: project.id)
      original_options = old.options

      migrate_up
      migrate_down
      old = reload_raw(old)

      expect(old.type).to eq("TeamSchedule")
      expect(old.project_id).to eq(project.id)
      expect(old.options).to eq(original_options)
    end
  end
end
