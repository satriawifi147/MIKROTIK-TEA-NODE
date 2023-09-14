#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2023 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module MeetingAgendaItems
  class ItemComponent::EditComponent < ApplicationComponent
    include ApplicationHelper
    include OpPrimer::ComponentHelpers

    def initialize(meeting_agenda_item:)
      super

      @meeting_agenda_item = meeting_agenda_item
      @type = if @meeting_agenda_item.work_package.present?
                :work_package
              else
                :simple
              end
    end

    def call
      render(Primer::Box.new(pl: 3)) do
        render(MeetingAgendaItems::FormComponent.new(
                 meeting: @meeting_agenda_item.meeting,
                 meeting_agenda_item: @meeting_agenda_item,
                 method: :put,
                 submit_path: meeting_agenda_item_path(@meeting_agenda_item.meeting, @meeting_agenda_item),
                 cancel_path: cancel_edit_meeting_agenda_item_path(@meeting_agenda_item.meeting, @meeting_agenda_item),
                 type: @type
               ))
      end
    end
  end
end