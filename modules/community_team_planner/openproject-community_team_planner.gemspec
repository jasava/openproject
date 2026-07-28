# frozen_string_literal: true

#-- copyright
# OpenProject Community Team Planner
# Copyright (C) the OpenProject community
#
# This is an independently maintained, Community-edition-only module. It is
# not part of, and does not depend on, OpenProject's Enterprise-gated Team
# Planner module (modules/team_planner). See
# docs/community-team-planner/adr-001-independent-module.md for the rationale.
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

Gem::Specification.new do |s|
  s.name        = "openproject-community_team_planner"
  s.version     = "1.0.0"
  s.authors     = "OpenProject community"
  s.email       = "info@openproject.com"
  s.summary     = "OpenProject Community Team Planner"
  s.description = "Provides a project-level team scheduling grid (Team Schedule) for the " \
                  "Community edition, independent of the Enterprise Team Planner module."
  s.license     = "GPL-3.0"

  s.files = Dir["{app,config,db,lib}/**/*"]
  s.metadata["rubygems_mfa_required"] = "true"
end
