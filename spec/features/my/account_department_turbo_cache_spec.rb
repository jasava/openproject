# frozen_string_literal: true

require "spec_helper"

# Regression test for OP-19674: the account page must not be served from a stale
# Turbo snapshot. Without `turbo-cache-control: no-cache`, a restoration visit
# (Back button / history navigation) re-renders the cached snapshot and shows an
# outdated department after it was changed out-of-band by an administrator.
RSpec.describe "My account department is not served stale from the Turbo cache", :js do
  shared_let(:admin) { create(:admin) }
  shared_let(:alpha) { create(:department, name: "Alpha department", members: [admin]) }
  shared_let(:beta) { create(:department, name: "Beta department") }

  before { login_as admin }

  it "shows the freshly changed department after a Turbo restoration visit" do
    visit my_account_path
    expect(page).to have_select("user[department_id]", disabled: true, selected: "Alpha department")

    # Leave via a Turbo visit so the account snapshot gets cached.
    page.execute_script("window.Turbo.visit('#{projects_path}')")
    expect(page).to have_current_path(projects_path, wait: 10, ignore_query: true)

    # Simulate an administrator moving the user to another department out-of-band.
    Departments::AddUserService
      .new(beta, user: admin)
      .call(user_id: admin.id, remove_from_previous_department: true)

    # Return through history: a Turbo restoration visit.
    page.go_back
    wait_for_network_idle

    expect(page).to have_select("user[department_id]", disabled: true, selected: "Beta department")
  end
end
