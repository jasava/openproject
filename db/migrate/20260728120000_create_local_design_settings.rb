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

class CreateLocalDesignSettings < ActiveRecord::Migration[8.1]
  def change # rubocop:disable Metrics/AbcSize
    create_table :local_design_settings do |t|
      t.string :theme, null: false, default: "OpenProject"
      t.jsonb :colors, null: false, default: {}

      t.string :logo
      t.string :logo_mobile
      t.string :favicon
      t.string :touch_icon

      t.string :pdf_logo
      t.string :pdf_cover
      t.string :pdf_footer
      t.string :pdf_cover_text_color
      t.string :pdf_font_regular
      t.string :pdf_font_bold
      t.string :pdf_font_italic
      t.string :pdf_font_bold_italic

      # Always 0 — combined with the unique index below, this is what makes
      # `LocalDesignSetting.current`'s find_or_create safe under concurrent
      # first-requests (see LocalDesignSetting#current for the full
      # rationale): a losing concurrent INSERT hits the unique index instead
      # of silently creating a second row.
      t.integer :singleton_guard, null: false, default: 0

      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :local_design_settings, :singleton_guard, unique: true
  end
end
