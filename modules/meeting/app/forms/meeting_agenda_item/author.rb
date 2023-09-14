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

class MeetingAgendaItem::Author < ApplicationForm
  form do |agenda_item_form|
    agenda_item_form.autocompleter(
      name: :author_id,
      label: MeetingAgendaItem.human_attribute_name(:author),
      visually_hide_label: true,
      autocomplete_options: {
        focusDirectly: false,
        resource: 'principals',
        filters: [{ name: 'member', operator: '=', values: [@project.id.to_s] }],
        model: { name: author_name },
        searchKey: 'any_name_attribute',
        disabled: @disabled,
        data: {
          'test-selector': 'op-agenda-items-user-autocomplete'
        }
      }
    )
  end

  def initialize(meeting_agenda_item:, project:, disabled: false)
    super()
    @meeting_agenda_item = meeting_agenda_item
    @project = project
    @disabled = disabled
  end

  def author_name
    return '' unless @meeting_agenda_item.author_id

    Principal.find_by(id: @meeting_agenda_item.author_id).name
  end
end