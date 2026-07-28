# frozen_string_literal: true

module TeamSchedules
  module Forms
    class AddRowForm < ApplicationForm
      form do |f|
        f.autocompleter(
          name: :principal_id,
          label: TeamSchedule.human_attribute_name(:assignee_ids),
          required: true,
          autocomplete_options: {
            component: "opce-user-autocompleter",
            url: ::API::V3::Utilities::PathHelper::ApiV3Path.principals,
            resource: "principals",
            searchKey: "any_name_attribute",
            filters: principal_filters,
            defaultData: true,
            focusDirectly: true,
            multiple: false,
            appendTo: "##{@dialog_id}"
          }
        )
      end

      def initialize(project:, existing_ids:, dialog_id:)
        super()
        @project = project
        @existing_ids = existing_ids
        @dialog_id = dialog_id
      end

      private

      # Project members only (never placeholder users), excluding rows
      # already on this schedule so the picker cannot offer a duplicate.
      def principal_filters
        filters = [
          { name: "type", operator: "=", values: %w[User] },
          { name: "status", operator: "=", values: [Principal.statuses[:active]] },
          { name: "member", operator: "=", values: [@project.id.to_s] }
        ]
        filters << { name: "id", operator: "!", values: @existing_ids.map(&:to_s) } if @existing_ids.any?
        filters
      end
    end
  end
end
