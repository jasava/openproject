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
  class BaseContract < ::ModelContract
    def self.model
      TeamSchedule
    end

    attribute :name

    stored_attribute :display_mode, store: :options
    stored_attribute :anchor_date,  store: :options
    stored_attribute :assignee_ids, store: :options

    validate :user_allowed_to_manage

    private

    # A private schedule may only be managed by its own owner; a public one by
    # anyone in the project holding the manage permission. Either way the
    # manage permission itself is required — it is never implied by ownership
    # alone (matches TeamSchedule#manageable?).
    def user_allowed_to_manage
      return if model.project.nil?
      return unless user.allowed_in_project?(:manage_community_team_planner, model.project)
      return if model.principal == user || model.public?

      errors.add :base, :error_unauthorized
    end
  end
end
