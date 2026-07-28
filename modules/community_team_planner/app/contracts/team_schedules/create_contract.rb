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
  class CreateContract < BaseContract
    attribute :project
    attribute :public

    validate :user_allowed_to_view

    private

    # Creation only requires the manage permission (checked by BaseContract's
    # user_allowed_to_manage once `principal` is set), but a brand-new record
    # has no persisted owner yet to compare against project membership, so
    # additionally require plain view access as a sanity check against a
    # project the user cannot see at all.
    def user_allowed_to_view
      return if model.project.nil?
      return if user.allowed_in_project?(:view_community_team_planner, model.project)

      errors.add :project, :error_unauthorized
    end
  end
end
