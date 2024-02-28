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

require 'spec_helper'

RSpec.describe WorkPackages::UpdateAncestorsService, type: :model do
  shared_association_default(:author, factory_name: :user) { create(:user) }
  shared_association_default(:project_with_types) { create(:project_with_types) }
  shared_association_default(:priority) { create(:priority) }
  shared_association_default(:open_status, factory_name: :status) { create(:status) }
  shared_let(:closed_status) { create(:closed_status) }
  shared_let(:user) { create(:user) }

  let(:estimated_hours) { [nil, nil, nil] }
  let(:done_ratios) { [0, 0, 0] }
  let(:statuses) { %i(open open open) }
  let(:aggregate_done_ratio) { 0.0 }
  let(:ignore_non_working_days) { [false, false, false] }

  def set_attributes_on(work_package, attributes)
    WorkPackages::SetAttributesService
      .new(user:,
           model: work_package,
           contract_class: WorkPackages::UpdateContract)
      .call(attributes)
  end

  describe 'done_ratio/estimated_hours/remaining_hours propagation' do
    context 'when setting estimated hours of a work package' do
      shared_let(:work_package) { create(:work_package, status: open_status) }

      before do
        set_attributes_on(work_package, estimated_hours: 2.0)
      end

      subject(:call_result) do
        described_class.new(user:, work_package:)
                       .call(%i(estimated_hours))
      end

      it 'sets its derived value to the same value' do
        expect { call_result }
          .to change(work_package, :derived_estimated_hours).from(nil).to(2.0)
        expect(call_result).to be_success
        expect(call_result.dependent_results).to be_empty
      end
    end

    context 'when setting the status of a work package' do
      shared_let(:open_status) { create(:status) }
      shared_let(:new_status_with_done_ratio) { create(:status, default_done_ratio: 100) }
      shared_let(:new_status_without_done_ratio) { create(:status) }

      shared_examples 'updates % complete of ancestors' do
        it 'considers the work package as the % complete ' \
           'attached to the status and sets the ' \
           'derived % complete value of the ancestors accordingly' do
          expect(child.done_ratio)
            .to eq(new_status_with_done_ratio.default_done_ratio)

          expect do
            updated_attributes = child.changes.keys.map(&:to_sym)
            described_class.new(user:, work_package: child)
                           .call(updated_attributes)
            parent.reload
          end
            .to change(parent, :derived_done_ratio).from(0).to(33)
        end
      end

      shared_examples 'does not update % complete of ancestors' do
        it 'does not consider the closed status a special value and ' \
           'does not set % complete of the work package or set the ' \
           'derived % complete value of the ancestors accordingly' do
          expect(child.done_ratio).to eq(0)

          expect do
            updated_attributes = child.changes.keys.map(&:to_sym)
            described_class.new(user:, work_package: child)
                           .call(updated_attributes)
            parent.reload
          end
            .not_to change(parent, :derived_done_ratio)
        end
      end

      context 'when using the "status-based" % complete mode',
              with_settings: { work_package_done_ratio: 'status' } do
        context 'with both parent and children having estimated hours set' do
          shared_let(:parent) do
            create(:work_package,
                   estimated_hours: 10.0,
                   remaining_hours: 10.0,
                   derived_estimated_hours: 15.0,
                   derived_remaining_hours: 15.0,
                   status: open_status)
          end
          shared_let(:child) do
            create(:work_package,
                   parent:,
                   estimated_hours: 5.0,
                   remaining_hours: 5.0,
                   status: open_status)
          end

          context 'when the new status has its default done ratio set' do
            context 'with the status field' do
              before do
                set_attributes_on(child, status: new_status_with_done_ratio)
              end

              include_examples 'updates % complete of ancestors'
            end

            context 'with the status_id field' do
              before do
                set_attributes_on(child, status_id: new_status_with_done_ratio.id)
              end

              include_examples 'updates % complete of ancestors'
            end
          end

          context 'when the closed status has no default done ratio set' do
            context 'with the status field' do
              before do
                set_attributes_on(child, status: new_status_without_done_ratio)
              end

              include_examples 'does not update % complete of ancestors'
            end

            context 'with the status_id field' do
              before do
                set_attributes_on(child, status_id: new_status_without_done_ratio.id)
              end

              include_examples 'does not update % complete of ancestors'
            end
          end
        end
      end
    end

    context 'for the new ancestor chain' do
      shared_examples 'attributes of parent having children' do
        before do
          children
        end

        it 'is a success' do
          expect(subject)
          .to be_success
        end

        it 'updated one work package - the parent' do
          expect(subject.dependent_results.map(&:result))
          .to contain_exactly(parent)
        end

        it 'has the expected derived done ratio' do
          expect(subject.dependent_results.first.result.derived_done_ratio)
          .to eq aggregate_done_ratio
        end

        it 'has the expected derived estimated_hours' do
          expect(subject.dependent_results.first.result.derived_estimated_hours)
          .to eq aggregate_estimated_hours
        end
      end

      let(:children) do
        (statuses.size - 1).downto(0).map do |i|
          create(:work_package,
                 parent:,
                 subject: "child #{i}",
                 status: statuses[i] == :open ? open_status : closed_status,
                 estimated_hours: estimated_hours[i],
                 done_ratio: done_ratios[i],
                 ignore_non_working_days:)
        end
      end

      shared_let(:parent) { create(:work_package, subject: 'parent', status: open_status) }

      subject do
        # In the call we only use estimated_hours (instead of also adding
        # done_ratio) in order to test that changes in estimated hours
        # trigger a recalculation of done_ratio, because estimated hours
        # act as weights in this calculation.
        described_class
          .new(user:,
               work_package: children.first)
          .call(%i(estimated_hours))
      end

      context 'with no estimated hours and no progress' do
        let(:statuses) { %i(open open open) }

        it 'is a success' do
          expect(subject)
          .to be_success
        end

        it 'does not update the parent' do
          expect(subject.dependent_results)
          .to be_empty
        end
      end

      context 'with 1 out of 3 tasks having estimated hours and 2 out of 3 tasks done' do
        let(:statuses) do
          %i(open closed closed)
        end

        it_behaves_like 'attributes of parent having children' do
          let(:estimated_hours) do
            [0.0, 2.0, 0.0]
          end

          # 66.67 rounded - previous wrong result: 133
          let(:aggregate_done_ratio) do
            67
          end
          let(:aggregate_estimated_hours) do
            2.0
          end
        end

        context 'with mixed nil and 0 values for estimated hours' do
          it_behaves_like 'attributes of parent having children' do
            let(:estimated_hours) do
              [nil, 2.0, 0.0]
            end

            # 66.67 rounded - previous wrong result: 100
            let(:aggregate_done_ratio) do
              67
            end
            let(:aggregate_estimated_hours) do
              2.0
            end
          end
        end

        context 'with parent having estimated hours' do
          before do
            parent.update(estimated_hours: 5.0)
          end

          it_behaves_like 'attributes of parent having children' do
            let(:estimated_hours) do
              [nil, 2.0, 0.0]
            end

            # 66.67 rounded - previous wrong result: 100
            let(:aggregate_done_ratio) do
              67
            end
            let(:aggregate_estimated_hours) do
              7.0
            end
          end
        end
      end

      context 'with some values same for done ratio' do
        it_behaves_like 'attributes of parent having children' do
          let(:done_ratios) { [20, 20, 50] }
          let(:estimated_hours) { [nil, nil, nil] }

          let(:aggregate_done_ratio) { 30 }
          let(:aggregate_estimated_hours) { nil }
        end
      end

      context 'with no estimated hours and 1.5 of the tasks done' do
        it_behaves_like 'attributes of parent having children' do
          let(:done_ratios) { [0, 50, 100] }

          let(:aggregate_done_ratio) { 50 }
          let(:aggregate_estimated_hours) { nil }
        end
      end

      context 'with estimated hours being 1, 2 and 5' do
        let(:estimated_hours) { [1, 2, 5] }

        context 'with the last 2 tasks at 100% progress' do
          it_behaves_like 'attributes of parent having children' do
            let(:done_ratios) { [0, 100, 100] }

            # (2 + 5 = 7) / 8 estimated hours done
            let(:aggregate_done_ratio) { 88 } # 87.5 rounded
            let(:aggregate_estimated_hours) { estimated_hours.sum }
          end
        end

        context 'with the last 2 tasks closed (therefore at 100%)' do
          it_behaves_like 'attributes of parent having children' do
            let(:statuses) { %i(open closed closed) }

            # (2 + 5 = 7) / 8 estimated hours done
            let(:aggregate_done_ratio) { 88 } # 87.5 rounded
            let(:aggregate_estimated_hours) { estimated_hours.sum }
          end
        end

        context 'with mixed done ratios, statuses' do
          it_behaves_like 'attributes of parent having children' do
            let(:done_ratios) { [50, 75, 42] }
            let(:statuses) { %i(open open closed) }

            #  50%       75%        100% (42 ignored)
            # (0.5 * 1 + 0.75 * 2 + 1 * 5 [since closed] = 7)
            # (0.5 + 1.5 + 5 = 7) / 8 estimated hours done
            let(:aggregate_done_ratio) { 88 } # 87.5 rounded
            let(:aggregate_estimated_hours) { estimated_hours.sum }
          end
        end
      end

      context 'with everything playing together' do
        it_behaves_like 'attributes of parent having children' do
          let(:statuses) { %i(open open closed open) }
          let(:done_ratios) { [0, 0, 0, 50] }
          let(:estimated_hours) { [0.0, 3.0, nil, 7.0] }

          # (0 * 5 + 0 * 3 + 1 * 5 + 0.5 * 7 = 8.5) / 20 est. hours done
          let(:aggregate_done_ratio) { 43 } # 42.5 rounded
          let(:aggregate_estimated_hours) { 10.0 }
        end
      end
    end

    context 'for the previous ancestors' do
      shared_let(:sibling_status) { open_status }
      shared_let(:sibling_done_ratio) { 50 }
      shared_let(:sibling_estimated_hours) { 7.0 }
      shared_let(:sibling_remaining_hours) { 3.5 }
      shared_let(:parent_estimated_hours) { 3.0 }

      shared_let(:grandparent) do
        create(:work_package,
               subject: 'grandparent')
      end
      shared_let(:parent) do
        create(:work_package,
               subject: 'parent',
               estimated_hours: parent_estimated_hours,
               parent: grandparent)
      end
      shared_let(:sibling) do
        create(:work_package,
               subject: 'sibling',
               parent:,
               status: sibling_status,
               done_ratio: sibling_done_ratio,
               estimated_hours: sibling_estimated_hours,
               remaining_hours: sibling_remaining_hours)
      end

      shared_let(:work_package) do
        create(:work_package,
               subject: 'subject - loses its parent',
               parent:)
      end

      subject do
        work_package.parent = nil
        work_package.save!

        described_class
          .new(user:,
               work_package:)
          .call(%i(parent))
      end

      it 'is successful' do
        expect(subject)
          .to be_success
      end

      it 'returns the former ancestors in the dependent results' do
        expect(subject.dependent_results.map(&:result))
          .to contain_exactly(parent, grandparent)
      end

      it 'updates the derived_done_ratio, derived_estimated_hours, and derived_remaining_hours of the former parent' do
        expect do
          subject
          parent.reload
        end
          .to change(parent, :derived_done_ratio).to(sibling_done_ratio)
          .and change(parent, :derived_estimated_hours).to(parent_estimated_hours + sibling_estimated_hours)
          .and change(parent, :derived_remaining_hours).to(sibling_remaining_hours)
      end

      it 'updates the derived_done_ratio, derived_estimated_hours, and derived_remaining_hours of the former grandparent' do
        expect do
          subject
          grandparent.reload
        end
          .to change(grandparent, :derived_done_ratio).to(sibling_done_ratio)
          .and change(grandparent, :derived_estimated_hours).to(parent_estimated_hours + sibling_estimated_hours)
          .and change(grandparent, :derived_remaining_hours).to(sibling_remaining_hours)
      end
    end

    context 'for new ancestors' do
      shared_let(:status) { open_status }
      shared_let(:done_ratio) { 50 }
      shared_let(:estimated_hours) { 7.0 }
      shared_let(:remaining_hours) { 3.5 }
      shared_let(:parent_estimated_hours) { 3.0 }
      shared_let(:parent_remaining_hours) { 1.5 }

      shared_let(:grandparent) do
        create(:work_package,
               subject: 'grandparent')
      end
      shared_let(:parent) do
        create(:work_package,
               subject: 'parent',
               estimated_hours: parent_estimated_hours,
               remaining_hours: parent_remaining_hours,
               parent: grandparent)
      end
      shared_let(:work_package) do
        create(:work_package,
               subject: 'subject - gains a new parent and grandparent',
               status:,
               done_ratio:,
               estimated_hours:,
               remaining_hours:)
      end

      shared_examples_for 'updates the attributes within the new hierarchy' do
        it 'is successful' do
          expect(subject)
            .to be_success
        end

        it 'returns the new ancestors in the dependent results' do
          expect(subject.dependent_results.map(&:result))
            .to contain_exactly(parent, grandparent)
        end

        it 'updates the derived_done_ratio, derived_estimated_hours, and derived_remaining_hours of the new parent' do
          expect do
            subject
            parent.reload
          end
            .to change(parent, :derived_done_ratio).to(done_ratio)
            .and change(parent, :derived_estimated_hours).to(parent_estimated_hours + estimated_hours)
            .and change(parent, :derived_remaining_hours).to(parent_remaining_hours + remaining_hours)
        end

        it 'updates the derived_done_ratio, derived_estimated_hours, and derived_remaining_hours ' \
           'of the new grandparent' do
          expect do
            subject
            grandparent.reload
          end
            .to change(grandparent, :derived_done_ratio).to(done_ratio)
            .and change(grandparent, :derived_estimated_hours).to(parent_estimated_hours + estimated_hours)
            .and change(grandparent, :derived_remaining_hours).to(parent_remaining_hours + remaining_hours)
        end
      end

      context 'if setting the parent' do
        subject do
          work_package.parent = parent
          work_package.save!

          described_class
            .new(user:,
                 work_package:)
            .call(%i(parent))
        end

        it_behaves_like 'updates the attributes within the new hierarchy'
      end

      context 'if setting the parent_id' do
        subject do
          work_package.parent_id = parent.id
          work_package.save!

          described_class
            .new(user:,
                 work_package:)
            .call(%i(parent_id))
        end

        it_behaves_like 'updates the attributes within the new hierarchy'
      end
    end

    context 'with old and new parent having a common ancestor' do
      shared_let(:status) { open_status }
      shared_let(:done_ratio) { 50 }
      shared_let(:estimated_hours) { 7.0 }
      shared_let(:remaining_hours) { 3.5 }
      shared_let(:new_done_ratio) { 80 }
      shared_let(:new_estimated_hours) { 10.0 }
      shared_let(:new_remaining_hours) { 2 }

      shared_let(:grandparent) do
        create(:work_package,
               subject: 'common grandparent',
               derived_done_ratio: done_ratio / 2, # two children having [done_ratio, 0]
               derived_estimated_hours: estimated_hours,
               derived_remaining_hours: remaining_hours)
      end
      shared_let(:old_parent) do
        create(:work_package,
               subject: 'old parent',
               parent: grandparent,
               derived_done_ratio: done_ratio,
               derived_estimated_hours: estimated_hours,
               derived_remaining_hours: remaining_hours)
      end
      shared_let(:new_parent) do
        create(:work_package,
               subject: 'new parent',
               parent: grandparent)
      end
      shared_let(:work_package) do
        create(:work_package,
               subject: 'subject - parent changes from old parent to new parent, same grandparent',
               parent: old_parent,
               status:,
               done_ratio:,
               estimated_hours:,
               remaining_hours:)
      end

      subject do
        work_package.parent = new_parent
        # In this test case, done_ratio, derived_estimated_hours, and
        # derived_remaining_hours would not inherently change on grandparent.
        # However, if work_package has siblings then changing its parent could
        #  cause done_ratio, derived_estimated_hours, and/or
        # derived_remaining_hours on grandparent to inherently change. To verify
        # that grandparent can be properly updated in that case without making
        # this test dependent on the implementation details of the calculations,
        # done_ratio, derived_estimated_hours, and derived_remaining_hours are
        # forced to change at the same time as the parent.
        work_package.done_ratio = new_done_ratio
        work_package.estimated_hours = new_estimated_hours
        work_package.remaining_hours = new_remaining_hours
        work_package.save!

        described_class
          .new(user:,
               work_package:)
          .call(%i(parent))
      end

      it 'is successful' do
        expect(subject)
          .to be_success
      end

      it 'returns both the former and new ancestors in the dependent results without duplicates' do
        expect(subject.dependent_results.map(&:result))
          .to contain_exactly(new_parent, grandparent, old_parent)
      end

      it 'updates the derived_done_ratio, derived_estimated_hours, and derived_remaining_hours ' \
         'of the former parent to 0' do
        expect do
          subject
          old_parent.reload
        end
          .to change(old_parent, :derived_done_ratio).to(0)
          .and change(old_parent, :derived_estimated_hours).to(nil)
          .and change(old_parent, :derived_remaining_hours).to(nil)
      end

      it 'updates the derived_done_ratio, derived_estimated_hours, and derived_remaining_hours of the new parent' do
        expect do
          subject
          new_parent.reload
        end
          .to change(new_parent, :derived_done_ratio).to(new_done_ratio)
          .and change(new_parent, :derived_estimated_hours).to(new_estimated_hours)
          .and change(new_parent, :derived_remaining_hours).to(new_remaining_hours)
      end

      it 'updates the derived_done_ratio, derived_estimated_hours, and derived_remaining_hours of the grandparent' do
        expect do
          subject
          grandparent.reload
        end
          .to change(grandparent, :derived_done_ratio).to(new_done_ratio / 2) # two children having [new_done_ratio, 0] now
          .and change(grandparent, :derived_estimated_hours).to(new_estimated_hours)
          .and change(grandparent, :derived_remaining_hours).to(new_remaining_hours)
      end
    end
  end

  describe 'remaining_hours propagation' do
    shared_let(:parent) { create(:work_package, subject: 'parent', status: open_status) }

    context 'when setting remaining hours of a work package' do
      before do
        parent.remaining_hours = 2.0
      end

      subject(:call_result) do
        described_class.new(user:, work_package: parent)
                       .call(%i(remaining_hours))
      end

      it 'sets its derived value to the same value' do
        expect { call_result }
          .to change(parent, :derived_remaining_hours).from(nil).to(2.0)
        expect(call_result).to be_success
        expect(call_result.dependent_results).to be_empty
      end
    end

    context 'for the new ancestors chain' do
      context 'with parent having no remaining work' do
        let_work_packages(<<~TABLE)
          hierarchy | remaining work |
          parent    |                |
            child1  |             0h |
            child2  |                |
            child3  |           2.5h |
        TABLE

        subject(:call_result) do
          described_class.new(user:, work_package: child1)
                         .call(%i(remaining_hours))
        end

        it 'sets parent derived remaining work to the sum of children remaining work' do
          expect(call_result).to be_success
          updated_work_packages = call_result.dependent_results.map(&:result)
          expect_work_packages(updated_work_packages, <<~TABLE)
            subject | derived remaining work
            parent  |                   2.5h
          TABLE
        end
      end

      context 'with parent having some remaining work' do
        let_work_packages(<<~TABLE)
          hierarchy | remaining work |
          parent    |          5.25h |
            child1  |             0h |
            child2  |                |
            child3  |           2.5h |
        TABLE

        subject(:call_result) do
          described_class.new(user:, work_package: child1)
                         .call(%i(remaining_hours))
        end

        it 'sets parent derived remaining work to the sum of itself and children remaining work' do
          expect(call_result).to be_success
          updated_work_packages = call_result.dependent_results.map(&:result)
          expect_work_packages(updated_work_packages, <<~TABLE)
            subject | derived remaining work
            parent  |                  7.75h
          TABLE
        end
      end

      context 'with parent and children having no remaining work' do
        let_work_packages(<<~TABLE)
          hierarchy | remaining work |
          parent    |                |
            child1  |                |
            child2  |                |
        TABLE

        subject(:call_result) do
          described_class.new(user:, work_package: child1)
                         .call(%i(remaining_hours))
        end

        it 'does not update the parent derived remaining work' do
          expect(call_result).to be_success
          expect(call_result.dependent_results).to be_empty
          expect_work_packages([parent.reload], <<~TABLE)
            subject | derived remaining work
            parent  |
          TABLE
        end
      end
    end
  end

  describe 'ignore_non_working_days propagation' do
    shared_let(:grandgrandparent) do
      create(:work_package,
             subject: 'grandgrandparent')
    end
    shared_let(:grandparent) do
      create(:work_package,
             subject: 'grandparent',
             parent: grandgrandparent)
    end
    shared_let(:parent) do
      create(:work_package,
             subject: 'parent',
             parent: grandparent)
    end
    shared_let(:sibling) do
      create(:work_package,
             subject: 'sibling',
             parent:)
    end
    shared_let(:work_package) do
      create(:work_package)
    end

    subject do
      work_package.parent = new_parent
      work_package.save!

      described_class
        .new(user:,
             work_package:)
        .call(%i(parent))
    end

    let(:new_parent) { parent }

    context 'for the previous ancestors (parent removed)' do
      let(:new_parent) { nil }

      before do
        work_package.parent = parent
        work_package.save

        [grandgrandparent, grandparent, parent, work_package].each do |wp|
          wp.update_column(:ignore_non_working_days, true)
        end

        [sibling].each do |wp|
          wp.update_column(:ignore_non_working_days, false)
        end
      end

      it 'is successful' do
        expect(subject)
          .to be_success
      end

      it 'returns the former ancestors in the dependent results' do
        expect(subject.dependent_results.map(&:result))
          .to contain_exactly(parent, grandparent, grandgrandparent)
      end

      it 'sets the ignore_non_working_days property of the former ancestor chain to the value of the
          only remaining child (former sibling)' do
        subject

        expect(parent.reload.ignore_non_working_days)
          .to be_falsey

        expect(grandparent.reload.ignore_non_working_days)
          .to be_falsey

        expect(grandgrandparent.reload.ignore_non_working_days)
          .to be_falsey

        expect(sibling.reload.ignore_non_working_days)
          .to be_falsey
      end
    end

    context 'for the new ancestors where the grandparent is on manual scheduling' do
      before do
        [grandgrandparent, work_package].each do |wp|
          wp.update_column(:ignore_non_working_days, true)
        end

        [grandparent, parent, sibling].each do |wp|
          wp.update_column(:ignore_non_working_days, false)
        end

        [grandparent].each do |wp|
          wp.update_column(:schedule_manually, true)
        end
      end

      it 'is successful' do
        expect(subject)
          .to be_success
      end

      it 'returns the former ancestors in the dependent results' do
        expect(subject.dependent_results.map(&:result))
          .to contain_exactly(parent)
      end

      it 'sets the ignore_non_working_days property of the new ancestors' do
        subject

        expect(parent.reload.ignore_non_working_days)
          .to be_truthy

        expect(grandparent.reload.ignore_non_working_days)
          .to be_falsey

        expect(grandgrandparent.reload.ignore_non_working_days)
          .to be_truthy

        expect(sibling.reload.ignore_non_working_days)
          .to be_falsey
      end
    end

    context 'for the new ancestors where the parent is on manual scheduling' do
      before do
        [grandgrandparent, grandparent, work_package].each do |wp|
          wp.update_column(:ignore_non_working_days, true)
        end

        [parent, sibling].each do |wp|
          wp.update_column(:ignore_non_working_days, false)
        end

        [parent].each do |wp|
          wp.update_column(:schedule_manually, true)
        end
      end

      it 'is successful' do
        expect(subject)
          .to be_success
      end

      it 'returns the former ancestors in the dependent results' do
        expect(subject.dependent_results.map(&:result))
          .to be_empty
      end

      it 'sets the ignore_non_working_days property of the new ancestors' do
        subject

        expect(parent.reload.ignore_non_working_days)
          .to be_falsey

        expect(grandparent.reload.ignore_non_working_days)
          .to be_truthy

        expect(grandgrandparent.reload.ignore_non_working_days)
          .to be_truthy

        expect(sibling.reload.ignore_non_working_days)
          .to be_falsey
      end
    end
  end
end
