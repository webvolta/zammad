require 'rails_helper'
require 'models/application_model_examples'

RSpec.describe Trigger, type: :model do
  subject(:trigger) { create(:trigger, condition: condition, perform: perform) }

  it_behaves_like 'ApplicationModel', can_assets: { selectors: %i[condition perform] }

  describe 'validation' do

    let(:condition) do
      { 'ticket.action' => { 'operator' => 'is', 'value' => 'create' } }
    end
    let(:perform) do
      { 'ticket.title' => { 'value'=>'triggered' } }
    end

    context 'notification.email' do
      context 'missing recipient' do

        let(:perform) do
          {
            'notification.email' => {
              'subject' => 'Hello',
              'body'    => 'World!'
            }
          }
        end

        it 'raises an error' do
          expect { trigger.save! }.to raise_error(Exceptions::UnprocessableEntity, 'Invalid perform notification.email, recipient is missing!')
        end
      end
    end

  end

  describe 'Send-email triggers' do
    before do
      described_class.destroy_all # Default DB state includes three sample triggers
      trigger # create subject trigger
    end

    let(:perform) do
      {
        'notification.email' => {
          'recipient' => 'ticket_customer',
          'subject'   => 'foo',
          'body'      => 'some body with &gt;snip&lt;#{article.body_as_html}&gt;/snip&lt;', # rubocop:disable Lint/InterpolationCheck
        }
      }
    end

    context 'for condition "ticket created"' do
      let(:condition) do
        { 'ticket.action' => { 'operator' => 'is', 'value' => 'create' } }
      end

      context 'when ticket is created directly' do
        let!(:ticket) { create(:ticket) }

        it 'fires (without altering ticket state)' do
          expect { Observer::Transaction.commit }
            .to change(Ticket::Article, :count).by(1)
            .and not_change { ticket.reload.state.name }.from('new')
        end
      end

      context 'when ticket is created via Channel::EmailParser.process' do
        before { create(:email_address, groups: [Group.first]) }

        let(:raw_email) { File.read(Rails.root.join('test/data/mail/mail001.box')) }

        it 'fires (without altering ticket state)' do
          expect { Channel::EmailParser.new.process({}, raw_email) }
            .to change(Ticket, :count).by(1)
            .and change { Ticket::Article.count }.by(2)

          expect(Ticket.last.state.name).to eq('new')
        end
      end

      context 'when ticket is created via Channel::EmailParser.process with inline image' do
        before { create(:email_address, groups: [Group.first]) }

        let(:raw_email) { File.read(Rails.root.join('test/data/mail/mail010.box')) }

        it 'fires (without altering ticket state)' do
          expect { Channel::EmailParser.new.process({}, raw_email) }
            .to change(Ticket, :count).by(1)
            .and change { Ticket::Article.count }.by(2)

          expect(Ticket.last.state.name).to eq('new')

          article = Ticket::Article.last
          expect(article.type.name).to eq('email')
          expect(article.sender.name).to eq('System')
          expect(article.attachments.count).to eq(1)
          expect(article.attachments[0].filename).to eq('image001.jpg')
          expect(article.attachments[0].preferences['Content-ID']).to eq('image001.jpg@01CDB132.D8A510F0')

          expect(article.body).to eq(<<~RAW.chomp
            some body with &gt;snip&lt;<div>
            <p>Herzliche Grüße aus Oberalteich sendet Herrn Smith</p>
            <p> </p>
            <p>Sepp Smith - Dipl.Ing. agr. (FH)</p>
            <p>Geschäftsführer der example Straubing-Bogen</p>
            <p>Klosterhof 1 | 94327 Bogen-Oberalteich</p>
            <p>Tel: 09422-505601 | Fax: 09422-505620</p>
            <p>Internet: <a href="http://example-straubing-bogen.de/" rel="nofollow noreferrer noopener" target="_blank">http://example-straubing-bogen.de</a></p>
            <p>Facebook: <a href="http://facebook.de/examplesrbog" rel="nofollow noreferrer noopener" target="_blank">http://facebook.de/examplesrbog</a></p>
            <p><b><img border="0" src="cid:image001.jpg@01CDB132.D8A510F0" alt="Beschreibung: Beschreibung: efqmLogo" style="width:60px;height:19px;"></b><b> - European Foundation für Quality Management</b></p>
            <p> </p>
            </div>&gt;/snip&lt;
          RAW
                                    )
        end
      end

      context 'notification.email recipient' do
        let!(:ticket) { create(:ticket) }
        let!(:recipient1) { create(:user, email: 'test1@zammad-test.com') }
        let!(:recipient2) { create(:user, email: 'test2@zammad-test.com') }
        let!(:recipient3) { create(:user, email: 'test3@zammad-test.com') }

        let(:perform) do
          {
            'notification.email' => {
              'recipient' => recipient,
              'subject'   => 'Hello',
              'body'      => 'World!'
            }
          }
        end

        before { Observer::Transaction.commit }

        context 'mix of recipient group keyword and single recipient users' do
          let(:recipient) { [ 'ticket_customer', "userid_#{recipient1.id}", "userid_#{recipient2.id}", "userid_#{recipient3.id}" ] }

          it 'contains all recipients' do
            expect(ticket.articles.last.to).to eq("#{ticket.customer.email}, #{recipient1.email}, #{recipient2.email}, #{recipient3.email}")
          end

          context 'duplicate recipient' do
            let(:recipient) { [ 'ticket_customer', "userid_#{ticket.customer.id}" ] }

            it 'contains only one recipient' do
              expect(ticket.articles.last.to).to eq(ticket.customer.email.to_s)
            end
          end
        end

        context 'list of single users only' do
          let(:recipient) { [ "userid_#{recipient1.id}", "userid_#{recipient2.id}", "userid_#{recipient3.id}" ] }

          it 'contains all recipients' do
            expect(ticket.articles.last.to).to eq("#{recipient1.email}, #{recipient2.email}, #{recipient3.email}")
          end

          context 'assets' do
            it 'resolves Users from recipient list' do
              expect(trigger.assets({})[:User].keys).to include(recipient1.id, recipient2.id, recipient3.id)
            end

            context 'single entry' do

              let(:recipient) { "userid_#{recipient1.id}" }

              it 'resolves User from recipient list' do
                expect(trigger.assets({})[:User].keys).to include(recipient1.id)
              end
            end
          end
        end

        context 'recipient group keyword only' do
          let(:recipient) { 'ticket_customer' }

          it 'contains matching recipient' do
            expect(ticket.articles.last.to).to eq(ticket.customer.email.to_s)
          end
        end
      end

      context 'active S/MIME integration' do
        before do
          Setting.set('smime_integration', true)

          create(:smime_certificate, :with_private, fixture: system_email_address)
          create(:smime_certificate, fixture: customer_email_address)
        end

        let(:system_email_address) { 'smime1@example.com' }
        let(:customer_email_address) { 'smime2@example.com' }

        let(:email_address) { create(:email_address, email: system_email_address) }

        let(:group) { create(:group, email_address: email_address) }
        let(:customer) { create(:customer, email: customer_email_address) }

        let(:security_preferences) { Ticket::Article.last.preferences[:security] }

        let(:perform) do
          {
            'notification.email' => {
              'recipient' => 'ticket_customer',
              'subject'   => 'Subject dummy.',
              'body'      => 'Body dummy.',
            }.merge(security_configuration)
          }
        end

        let!(:ticket) { create(:ticket, group: group, customer: customer) }

        context 'sending articles' do

          before do
            Observer::Transaction.commit
          end

          context 'expired certificate' do

            let(:system_email_address) { 'expiredsmime1@example.com' }

            let(:security_configuration) do
              {
                'sign'       => 'always',
                'encryption' => 'always',
              }
            end

            it 'creates unsigned article' do
              expect(security_preferences[:sign][:success]).to be false
              expect(security_preferences[:encryption][:success]).to be true
            end
          end

          context 'sign and encryption not set' do

            let(:security_configuration) { {} }

            it 'does not sign or encrypt' do
              expect(security_preferences[:sign][:success]).to be false
              expect(security_preferences[:encryption][:success]).to be false
            end
          end

          context 'sign and encryption disabled' do
            let(:security_configuration) do
              {
                'sign'       => 'no',
                'encryption' => 'no',
              }
            end

            it 'does not sign or encrypt' do
              expect(security_preferences[:sign][:success]).to be false
              expect(security_preferences[:encryption][:success]).to be false
            end
          end

          context 'sign is enabled' do
            let(:security_configuration) do
              {
                'sign'       => 'always',
                'encryption' => 'no',
              }
            end

            it 'signs' do
              expect(security_preferences[:sign][:success]).to be true
              expect(security_preferences[:encryption][:success]).to be false
            end
          end

          context 'encryption enabled' do

            let(:security_configuration) do
              {
                'sign'       => 'no',
                'encryption' => 'always',
              }
            end

            it 'encrypts' do
              expect(security_preferences[:sign][:success]).to be false
              expect(security_preferences[:encryption][:success]).to be true
            end
          end

          context 'sign and encryption enabled' do

            let(:security_configuration) do
              {
                'sign'       => 'always',
                'encryption' => 'always',
              }
            end

            it 'signs and encrypts' do
              expect(security_preferences[:sign][:success]).to be true
              expect(security_preferences[:encryption][:success]).to be true
            end
          end
        end

        context 'discard' do

          context 'sign' do

            let(:security_configuration) do
              {
                'sign' => 'discard',
              }
            end

            context 'group without certificate' do
              let(:group) { create(:group) }

              it 'does not fire' do
                expect { Observer::Transaction.commit }
                  .to change(Ticket::Article, :count).by(0)
              end
            end
          end

          context 'encryption' do

            let(:security_configuration) do
              {
                'encryption' => 'discard',
              }
            end

            context 'customer without certificate' do
              let(:customer) { create(:customer) }

              it 'does not fire' do
                expect { Observer::Transaction.commit }
                  .to change(Ticket::Article, :count).by(0)
              end
            end
          end

          context 'mixed' do

            context 'sign' do

              let(:security_configuration) do
                {
                  'encryption' => 'always',
                  'sign'       => 'discard',
                }
              end

              context 'group without certificate' do
                let(:group) { create(:group) }

                it 'does not fire' do
                  expect { Observer::Transaction.commit }
                    .to change(Ticket::Article, :count).by(0)
                end
              end
            end

            context 'encryption' do

              let(:security_configuration) do
                {
                  'encryption' => 'discard',
                  'sign'       => 'always',
                }
              end

              context 'customer without certificate' do
                let(:customer) { create(:customer) }

                it 'does not fire' do
                  expect { Observer::Transaction.commit }
                    .to change(Ticket::Article, :count).by(0)
                end
              end
            end
          end
        end
      end
    end

    context 'for condition "ticket updated"' do
      let(:condition) do
        { 'ticket.action' => { 'operator' => 'is', 'value' => 'update' } }
      end

      let!(:ticket) { create(:ticket).tap { Observer::Transaction.commit } }

      context 'when new article is created directly' do
        context 'with empty #preferences hash' do
          let!(:article) { create(:ticket_article, ticket: ticket) }

          it 'fires (without altering ticket state)' do
            expect { Observer::Transaction.commit }
              .to change { ticket.reload.articles.count }.by(1)
              .and not_change { ticket.reload.state.name }.from('new')
          end
        end

        context 'with #preferences { "send-auto-response" => false }' do
          let!(:article) do
            create(:ticket_article,
                   ticket:      ticket,
                   preferences: { 'send-auto-response' => false })
          end

          it 'does not fire' do
            expect { Observer::Transaction.commit }
              .not_to change { ticket.reload.articles.count }
          end
        end
      end

      context 'when new article is created via Channel::EmailParser.process' do
        context 'with a regular message' do
          let!(:article) do
            create(:ticket_article,
                   ticket:     ticket,
                   message_id: raw_email[/(?<=^References: )\S*/],
                   subject:    raw_email[/(?<=^Subject: Re: ).*$/])
          end

          let(:raw_email) { File.read(Rails.root.join('test/data/mail/mail005.box')) }

          it 'fires (without altering ticket state)' do
            expect { Channel::EmailParser.new.process({}, raw_email) }
              .to not_change { Ticket.count }
              .and change { ticket.reload.articles.count }.by(2)
              .and not_change { ticket.reload.state.name }.from('new')
          end
        end

        context 'with delivery-failed "bounce message"' do
          let!(:article) do
            create(:ticket_article,
                   ticket:     ticket,
                   message_id: raw_email[/(?<=^Message-ID: )\S*/])
          end

          let(:raw_email) { File.read(Rails.root.join('test/data/mail/mail055.box')) }

          it 'does not fire' do
            expect { Channel::EmailParser.new.process({}, raw_email) }
              .to change { ticket.reload.articles.count }.by(1)
          end
        end
      end
    end

    context 'with condition execution_time.calendar_id' do
      let(:calendar) { create(:calendar) }
      let(:perform) do
        { 'ticket.title'=>{ 'value'=>'triggered' } }
      end
      let!(:ticket) { create(:ticket, title: 'Test Ticket') }

      context 'is in working time' do
        let(:condition) do
          { 'ticket.state_id' => { 'operator' => 'is', 'value' => Ticket::State.all.pluck(:id) }, 'execution_time.calendar_id' => { 'operator' => 'is in working time', 'value' => calendar.id } }
        end

        it 'does trigger only in working time' do
          travel_to Time.zone.parse('2020-02-12T12:00:00Z0')
          expect { Observer::Transaction.commit }.to change { ticket.reload.title }.to('triggered')
        end

        it 'does not trigger out of working time' do
          travel_to Time.zone.parse('2020-02-12T02:00:00Z0')
          Observer::Transaction.commit
          expect(ticket.reload.title).to eq('Test Ticket')
        end
      end

      context 'is not in working time' do
        let(:condition) do
          { 'execution_time.calendar_id' => { 'operator' => 'is not in working time', 'value' => calendar.id } }
        end

        it 'does not trigger in working time' do
          travel_to Time.zone.parse('2020-02-12T12:00:00Z0')
          Observer::Transaction.commit
          expect(ticket.reload.title).to eq('Test Ticket')
        end

        it 'does trigger out of working time' do
          travel_to Time.zone.parse('2020-02-12T02:00:00Z0')
          expect { Observer::Transaction.commit }.to change { ticket.reload.title }.to('triggered')
        end
      end
    end

    context 'with article last sender equals system address' do
      let!(:ticket) { create(:ticket) }
      let(:perform) do
        {
          'notification.email' => {
            'recipient' => 'article_last_sender',
            'subject'   => 'foo last sender',
            'body'      => 'some body with &gt;snip&lt;#{article.body_as_html}&gt;/snip&lt;', # rubocop:disable Lint/InterpolationCheck
          }
        }
      end
      let(:condition) do
        { 'ticket.state_id' => { 'operator' => 'is', 'value' => Ticket::State.all.pluck(:id) } }
      end
      let!(:system_address) do
        create(:email_address)
      end

      context 'article with from equal to the a system address' do
        let!(:article) do
          create(:ticket_article,
                 ticket: ticket,
                 from:   system_address.email,)
        end

        it 'does not trigger because of the last article is created my system address' do
          expect { Observer::Transaction.commit }.to change { ticket.reload.articles.count }.by(0)
          expect(Ticket::Article.where(ticket: ticket).last.subject).not_to eq('foo last sender')
          expect(Ticket::Article.where(ticket: ticket).last.to).not_to eq(system_address.email)
        end
      end

      context 'article with reply_to equal to the a system address' do
        let!(:article) do
          create(:ticket_article,
                 ticket:   ticket,
                 from:     system_address.email,
                 reply_to: system_address.email,)
        end

        it 'does not trigger because of the last article is created my system address' do
          expect { Observer::Transaction.commit }.to change { ticket.reload.articles.count }.by(0)
          expect(Ticket::Article.where(ticket: ticket).last.subject).not_to eq('foo last sender')
          expect(Ticket::Article.where(ticket: ticket).last.to).not_to eq(system_address.email)
        end
      end
    end
  end

  context 'with pre condition current_user.id' do
    let(:perform) do
      { 'ticket.title'=>{ 'value'=>'triggered' } }
    end

    let(:user) do
      user = create(:agent)
      user.roles.first.groups << group
      user
    end

    let(:group) { Group.first }

    let(:ticket) do
      create(:ticket,
             title: 'Test Ticket', group: group,
             owner_id: user.id, created_by_id: user.id, updated_by_id: user.id)
    end

    shared_examples 'successful trigger' do |attribute:|
      let(:attribute) { attribute }

      let(:condition) do
        { attribute => { operator: 'is', pre_condition: 'current_user.id', value: '', value_completion: '' } }
      end

      it "for #{attribute}" do
        ticket && trigger
        expect { Observer::Transaction.commit }.to change { ticket.reload.title }.to('triggered')
      end
    end

    it_behaves_like 'successful trigger', attribute: 'ticket.updated_by_id'
    it_behaves_like 'successful trigger', attribute: 'ticket.owner_id'
  end
end
