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
  class CreateContract < BaseContract
    attribute :public

    validate :user_may_use_team_schedule

    private

    # BaseContract's user_allowed_to_manage (ownership) trivially passes for
    # any brand-new record once SetAttributesService assigns `principal =
    # user` — this is the actual sanity check for creation: the user must be
    # able to reach Team Schedule at all (the same check
    # GlobalTeamPlannerController's entry gate uses), otherwise anyone could
    # create a view even without permission to view any work package.
    def user_may_use_team_schedule
      return if user.allowed_in_any_work_package?(:view_work_packages)

      errors.add :base, :error_unauthorized
    end
  end
end
