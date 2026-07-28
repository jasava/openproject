# frozen_string_literal: true

#-- copyright
# OpenProject Local Design
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

# Independent copy of Admin::DesignHeaderComponent's shape (title,
# breadcrumbs, description, tab nav) rather than a reuse of that class — it
# lives alongside the Enterprise CustomStyle admin page and this feature
# should not carry a dependency on anything under that page's namespace,
# even a currently-unguarded one. See docs/local-design/architecture-analysis.md.
module LocalDesign
  class HeaderComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers
    include ApplicationHelper
    include TabsHelper

    def initialize(tabs: [])
      super
      @tabs = tabs
    end
  end
end
