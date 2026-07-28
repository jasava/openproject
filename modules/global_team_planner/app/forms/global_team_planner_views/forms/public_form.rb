# frozen_string_literal: true

module GlobalTeamPlannerViews
  module Forms
    class PublicForm < ApplicationForm
      form do |f|
        f.check_box(
          name: :public,
          label: GlobalTeamPlannerView.human_attribute_name(:public),
          caption: I18n.t("global_team_planner.new_dialog.public_label")
        )
      end
    end
  end
end
