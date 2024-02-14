#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2024 the OpenProject GmbH
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

module Admin::Settings
  class AttachmentsSettingsController < ::Admin::SettingsController
    menu_item :settings_attachments

    before_action :check_clamav, only: %i[update], if: -> { params[:settings] }

    def default_breadcrumb
      t(:'attributes.attachments')
    end

    def av_form
      selected = params.dig(:settings, :antivirus_scan_mode)&.to_sym || :disabled

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(:attachments_av_subform,
                                                    partial: "admin/settings/attachments_settings/av_form",
                                                    locals: { selected: })
        end
      end
    end

    private

    def check_clamav
      return if params[:settings][:antivirus_scan_mode] == "disabled"

      service = Attachments::ClamAVService.new(params[:settings][:antivirus_scan_mode],
                                               params[:settings][:antivirus_scan_target])

      service.ping
    rescue ClamAV::Error
      flash[:error] = t(:'attachments.settings.antivirus_scan_target_unreachable')
      redirect_to admin_settings_path(tab: "attachments")
    end

    def settings_params
      super.tap do |settings|
        settings["attachment_whitelist"] = settings["attachment_whitelist"].split(/\r?\n/)
      end
    end
  end
end
