# frozen_string_literal: true

module TeamSchedules
  module Forms
    class DetailsForm < ApplicationForm
      form do |f|
        f.text_field(
          name: :name,
          label: TeamSchedule.human_attribute_name(:name),
          required: true,
          autofocus: true,
          autocomplete: "off",
          input_width: :large
        )
      end
    end
  end
end
