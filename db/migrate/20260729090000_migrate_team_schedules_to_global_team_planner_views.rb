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

# Migrates any existing project-scoped `TeamSchedule` (STI on `persisted_views`,
# from the now-removed `community_team_planner` module) into the new global
# `GlobalTeamPlannerView` STI type: renames the STI `type`, nullifies
# `project_id`, and seeds `selected_project_ids`/`project_scope_mode` from the
# old single `project_id` so no existing saved schedule silently disappears
# or silently expands to "all projects" — it keeps showing exactly the one
# project it always did, now stored as data instead of a foreign key.
#
# `up` is safe to run against a database that never had the old module
# installed (finds zero rows, does nothing). `down` reverses it exactly
# (including restoring `project_id`) as long as `selected_project_ids` was
# not edited in between — see the migration test for the documented
# rollback caveat when a migrated view's project selection has since changed.
class MigrateTeamSchedulesToGlobalTeamPlannerViews < ActiveRecord::Migration[8.1]
  class MigrationPersistedView < ActiveRecord::Base
    self.table_name = "persisted_views"

    # Without this, ActiveRecord treats the `type` column as a Rails STI
    # discriminator and tries to `constantize` every row's `type` value into
    # a real Ruby class when loading it — which raises
    # ActiveRecord::SubclassNotFound for "TeamSchedule" once the old
    # community_team_planner module (and its TeamSchedule model) is no longer
    # bundled/autoloadable. This migration only ever reads/writes the `type`
    # column as a plain string, so STI class resolution must stay off.
    self.inheritance_column = nil
  end

  def up
    MigrationPersistedView.where(type: "TeamSchedule").find_each do |view|
      options = (view.options || {}).merge(
        "project_scope_mode" => "selected",
        "selected_project_ids" => [view.project_id].compact
      )

      view.update_columns(type: "GlobalTeamPlannerView", project_id: nil, options:)
    end
  end

  def down
    MigrationPersistedView.where(type: "GlobalTeamPlannerView").find_each do |view|
      options = view.options || {}
      selected = json_array(options["selected_project_ids"])
      restored_project_id = selected.first

      new_options = options.except("project_scope_mode", "selected_project_ids")
      view.update_columns(type: "TeamSchedule", project_id: restored_project_id, options: new_options)
    end
  end

  private

  # `GlobalTeamPlannerView`'s `store_attribute :options, :selected_project_ids,
  # :json` writes that sub-key as a JSON-encoded *string* nested inside the
  # `options` jsonb column (a quirk of that gem's `:json` store type), while
  # this migration's own `up` writes it as a native JSON array directly via
  # `update_columns`. A row may carry either shape depending on whether it was
  # last touched by a genuine app save or by this migration, so `down` must
  # accept both.
  def json_array(value)
    case value
    when String then JSON.parse(value)
    when Array then value
    else []
    end
  rescue JSON::ParserError
    []
  end
end
