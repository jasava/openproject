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

# Not part of the ported-files list in the rework brief, but required by
# NewDialogComponent/EditDialogComponent below (both render a footer exactly
# like the old TeamSchedules::FooterComponent did) and carries no
# project-scoping assumption of its own, so it is ported verbatim (namespace
# and copyright header only).
module GlobalTeamPlanner
  class FooterComponent < ApplicationComponent
    include OpTurbo::Streamable
    include OpPrimer::ComponentHelpers

    def initialize(dialog_id:, form_id:, footer_id:, submit_label:)
      super

      @dialog_id = dialog_id
      @form_id = form_id
      @footer_id = footer_id
      @submit_label = submit_label
    end

    def wrapper_key
      @footer_id
    end

    def call
      component_wrapper do
        component_collection do |buttons|
          buttons.with_component(
            Primer::Beta::Button.new(data: { close_dialog_id: @dialog_id })
          ) { I18n.t(:button_cancel) }

          buttons.with_component(
            Primer::Beta::Button.new(
              scheme: :primary,
              form: @form_id,
              data: { turbo: true },
              type: :submit
            )
          ) { @submit_label }
        end
      end
    end
  end
end
