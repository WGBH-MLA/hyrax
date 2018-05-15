RSpec.describe Hyrax::Transactions::CreateWork do
  subject(:transaction) { described_class.new }
  let(:template)        { Hyrax::PermissionTemplate.find_by!(source_id: work.admin_set_id) }
  let(:work)            { build(:work_without_access) }
  let(:xmas)            { DateTime.parse('2018-12-25 11:30').iso8601 }

  before do
    Hyrax::PermissionTemplate
      .create!(source_id: AdminSet.find_or_create_default_admin_set_id)
  end

  describe '#call' do
    context 'with an invalid work' do
      let(:work) { build(:invalid_generic_work) }

      it 'is a failure' do
        expect(transaction.call(work)).to be_failure
      end

      it 'does not save the work' do
        expect { transaction.call(work) }.not_to change { work.new_record? }.from true
      end

      it 'gives errors for the work' do
        expect(transaction.call(work).failure).to eq work.errors
      end
    end

    context 'with a depositor' do
      let(:depositor) { create(:admin) }

      it 'is a success' do
        result = transaction
                   .with_step_args(set_depositor: [{ depositor: depositor }])
                   .call(work)

        expect(result).to be_success
      end

      it 'sets the depositor' do
        transaction
          .with_step_args(set_depositor: [{ depositor: depositor }])
          .call(work)

        expect(work.depositor).to eq depositor.user_key
      end
    end

    context 'with valid attributes' do
      let(:attributes) do
        attributes_for(:generic_work, creator: ['Moomin'], subject: ['Snorks'])
      end

      it 'is a success' do
        result = transaction
                   .with_step_args(apply_attributes: [{ attributes: attributes }])
                   .call(work)

        expect(result).to be_success
      end

      it 'applies the attributes' do
        transaction
          .with_step_args(apply_attributes: [{ attributes: attributes }])
          .call(work)

        expect(work).to have_attributes attributes
      end
    end

    context 'with missing attributes' do
      let(:attributes) { { title: ['moomin'], not_real: ['very fake'] } }

      it 'is a failure' do
        result = transaction
                   .with_step_args(apply_attributes: [{ attributes: attributes }])
                   .call(work)

        expect(result).to be_failure
      end
    end

    context 'with invalid attributes' do
      let(:attributes) { attributes_for(:invalid_generic_work) }

      it 'is a failure' do
        result = transaction
                   .with_step_args(apply_attributes: [{ attributes: attributes }])
                   .call(work)

        expect(result).to be_failure
      end
    end

    it 'is a success' do
      expect(transaction.call(work)).to be_success
    end

    it 'persists the work' do
      expect { transaction.call(work) }
        .to change { work.persisted? }
        .to true
    end

    it 'sets visibility to restricted by default' do
      expect { transaction.call(work) }
        .not_to change { work.visibility }
        .from Hydra::AccessControls::AccessRight::VISIBILITY_TEXT_VALUE_PRIVATE
    end

    it 'sets the default admin set' do
      expect { transaction.call(work) }
        .to change { work.admin_set&.id }
        .to AdminSet.find_or_create_default_admin_set_id
    end

    it 'sets the modified time using Hyrax::TimeService' do
      allow(Hyrax::TimeService).to receive(:time_in_utc).and_return(xmas)

      expect { transaction.call(work) }.to change { work.date_modified }.to xmas
    end

    it 'sets the created time using Hyrax::TimeService' do
      allow(Hyrax::TimeService).to receive(:time_in_utc).and_return(xmas)

      expect { transaction.call(work) }.to change { work.date_uploaded }.to xmas
    end

    it 'applies permission template'
  end

  context 'when visibility is set' do
    let(:visibility) { Hydra::AccessControls::AccessRight::VISIBILITY_TEXT_VALUE_PUBLIC }

    before { work.visibility = visibility }

    it 'keeps the visibility' do
      expect { transaction.call(work) }
        .not_to change { work.visibility }
        .from visibility
    end
  end

  context 'when adding to works' do
    let(:other_works)    { create_list(:generic_work, 2) }
    let(:other_work_ids) { other_works.map(&:id) }

    it 'adds new work as member' do
      result = transaction
                 .with_step_args(add_to_works: [{ work_ids: other_work_ids }])
                 .call(work)

      expect(work.member_of.map(&:id)).to contain_exactly(*other_work_ids)
    end
  end

  context 'with an admin set' do
    let(:admin_set) { AdminSet.find(template.source_id) }
    let(:template)  { create(:permission_template, with_admin_set: true) }
    let(:work)      { build(:generic_work, admin_set: admin_set) }

    context 'without a permission template' do
      let(:admin_set) { create(:admin_set, with_permission_template: false) }

      it 'is a failure' do
        expect(transaction.call(work)).to be_failure
      end

      it 'is does not persist the work' do
        expect { transaction.call(work) }
          .not_to change { work.persisted? }
          .from false
      end
    end

    it 'is a success' do
      expect(transaction.call(work)).to be_success
    end

    it 'retains the set admin set' do
      expect { transaction.call(work) }
        .not_to change { work.admin_set&.id }
        .from admin_set.id
    end

    context 'with users and groups' do
      let(:manage_users) { create_list(:user, 2) }
      let(:view_users)   { create_list(:user, 2) }

      let(:manage_groups) { ['manage_group_1', 'manage_group_2'] }
      let(:view_groups)   { ['view_group_1', 'view_group_2'] }

      let(:template) do
        create(:permission_template,
               with_admin_set: true,
               manage_users:  manage_users,
               manage_groups: manage_groups,
               view_users:    view_users,
               view_groups:   view_groups)
      end

      it 'assigns edit users from template' do
        expect { transaction.call(work) }
          .to change { work.edit_users }
          .to include(*manage_users.map(&:user_key))
      end

      it 'assigns edit groups from template' do
        expect { transaction.call(work) }
          .to change { work.edit_groups }
          .to include(*manage_groups)
      end

      it 'assigns read users from template' do
        expect { transaction.call(work) }
          .to change { work.read_users }
          .to include(*view_users.map(&:user_key))
      end

      it 'assigns read groups from template' do
        expect { transaction.call(work) }
          .to change { work.read_groups }
          .to include(*view_groups)
      end
    end
  end
end