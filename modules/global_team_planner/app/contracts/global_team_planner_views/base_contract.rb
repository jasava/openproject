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

module GlobalTeamPlannerViews
  class BaseContract < ::ModelContract
    def self.model
      GlobalTeamPlannerView
    end

    attribute :name

    stored_attribute :display_mode,        store: :options
    stored_attribute :anchor_date,         store: :options
    stored_attribute :assignee_ids,        store: :options
    stored_attribute :project_scope_mode,  store: :options
    stored_attribute :selected_project_ids, store: :options
    stored_attribute :show_unassigned,     store: :options
    stored_attribute :group_by_project,    store: :options

    validate :user_allowed_to_manage

    private

    # Deliberately just GlobalTeamPlannerView#manageable? (owner-only) —
    # there is no single project whose "manage" permission could govern a
    # cross-project view, unlike the old project-scoped TeamSchedule. See
    # the model's own comment and docs/global-team-planner/permissions.md.
    def user_allowed_to_manage
      return if model.manageable?(user)

      errors.add :base, :error_unauthorized
    end
  end
end
