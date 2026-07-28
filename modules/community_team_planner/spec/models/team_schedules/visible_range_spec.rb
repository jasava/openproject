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

require "spec_helper"

RSpec.describe TeamSchedules::VisibleRange do
  # A fixed Wednesday so beginning_of_week (Monday) math is unambiguous.
  let(:anchor) { Date.new(2026, 8, 5) }
  let(:working_days) { WorkPackages::Shared::WorkingDays.new }

  subject(:range) { described_class.new(display_mode:, anchor_date: anchor, working_days:) }

  before do
    # Standard Mon-Fri working week, Sat/Sun non-working — set explicitly so
    # the spec does not depend on instance defaults, and to prove the
    # calculation goes through configuration rather than hardcoding weekends.
    allow(working_days).to receive(:working?) { |date| !date.saturday? && !date.sunday? }
  end

  describe "one_week" do
    let(:display_mode) { "one_week" }

    it "spans the anchor's full calendar week, Monday first" do
      expect(range.days.size).to eq(7)
      expect(range.days.first).to eq(Date.new(2026, 8, 3)) # Monday
      expect(range.days.last).to eq(Date.new(2026, 8, 9))  # Sunday
      expect(range.range_start).to eq(Date.new(2026, 8, 3))
      expect(range.range_end).to eq(Date.new(2026, 8, 9))
    end
  end

  describe "two_weeks" do
    let(:display_mode) { "two_weeks" }

    it "spans 14 calendar days starting on the anchor week's Monday" do
      expect(range.days.size).to eq(14)
      expect(range.days.first).to eq(Date.new(2026, 8, 3))
      expect(range.days.last).to eq(Date.new(2026, 8, 16))
    end
  end

  describe "four_weeks" do
    let(:display_mode) { "four_weeks" }

    it "spans 28 calendar days starting on the anchor week's Monday" do
      expect(range.days.size).to eq(28)
      expect(range.days.first).to eq(Date.new(2026, 8, 3))
      expect(range.days.last).to eq(Date.new(2026, 8, 30))
    end
  end

  describe "work_week" do
    let(:display_mode) { "work_week" }

    it "only includes the configured working days of the anchor's week" do
      expect(range.days).to eq(
        [Date.new(2026, 8, 3), Date.new(2026, 8, 4), Date.new(2026, 8, 5),
         Date.new(2026, 8, 6), Date.new(2026, 8, 7)]
      )
    end

    it "still reports the full week as its start/end for card-clipping purposes" do
      expect(range.range_start).to eq(Date.new(2026, 8, 3))
      expect(range.range_end).to eq(Date.new(2026, 8, 9))
    end

    context "when Friday is also configured as non-working" do
      before do
        allow(working_days).to receive(:working?) { |date| (1..4).cover?(date.wday) } # Mon-Thu only
      end

      it "does not assume Saturday/Sunday are the only non-working days" do
        expect(range.days).to eq(
          [Date.new(2026, 8, 3), Date.new(2026, 8, 4), Date.new(2026, 8, 5), Date.new(2026, 8, 6)]
        )
      end
    end
  end

  describe "navigation" do
    let(:display_mode) { "two_weeks" }

    it "#next_anchor jumps forward by the mode's day count" do
      expect(range.next_anchor).to eq(anchor + 14)
    end

    it "#previous_anchor jumps back by the mode's day count" do
      expect(range.previous_anchor).to eq(anchor - 14)
    end

    context "for work_week" do
      let(:display_mode) { "work_week" }

      it "jumps by a full 7-day week regardless of how many days are working days" do
        expect(range.next_anchor).to eq(anchor + 7)
        expect(range.previous_anchor).to eq(anchor - 7)
      end
    end
  end
end
