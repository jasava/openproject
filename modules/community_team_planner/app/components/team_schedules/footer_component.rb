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
