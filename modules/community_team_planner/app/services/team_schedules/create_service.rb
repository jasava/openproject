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
  class CreateService < ::BaseServices::Create
    protected

    # STI sets `type` during `.new`, before the model is extended with
    # ChangedBySystem; mark that initial change as system-made so the contract
    # does not flag `type` as a user-written readonly attribute (mirrors
    # ResourcePlanners::CreateService, the established pattern for
    # PersistedView STI subclasses in this codebase).
    def instance(_params)
      schedule = model || TeamSchedule.new
      schedule.extend(OpenProject::ChangedBySystem) unless schedule.is_a?(OpenProject::ChangedBySystem)
      schedule.changed_by_system(schedule.changes)
      schedule
    end
  end
end
