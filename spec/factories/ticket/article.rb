FactoryBot.define do
  factory :'ticket/article', aliases: %i[ticket_article] do
    transient do
      type_name   { 'email' }
      sender_name { 'Customer' }
    end

    association :ticket, strategy: :create # or else build(:ticket_article).save fails
    from          { 'factory-customer-1@example.com' }
    to            { 'factory-customer-1@example.com' }
    subject       { 'factory article' }
    message_id    { 'factory@id_com_1' }
    body          { 'some message 123' }
    internal      { false }
    sender        { Ticket::Article::Sender.find_by(name: sender_name) }
    type          { Ticket::Article::Type.find_by(name: type_name) }
    updated_by_id { 1 }
    created_by_id { 1 }

    factory :twitter_article do
      transient do
        type_name { 'twitter status' }
      end

      association :ticket, factory: :twitter_ticket
      message_id { '775410014383026176' }
      body { Faker::Lorem.sentence }
      sender_name { 'Agent' }

      trait :reply do
        in_reply_to { Faker::Number.number(19) }
      end
    end

    factory :twitter_dm_article do
      transient do
        type_name { 'twitter direct-message' }
      end

      association :ticket, factory: :twitter_ticket
      body { Faker::Lorem.sentence }

      trait :pending_delivery do
        transient do
          recipient { create(:twitter_authorization) }
          sender_id { Faker::Number.number(10) }
        end

        from         { ticket.owner.fullname }
        to           { recipient.username }
        in_reply_to  { Faker::Number.number(19) }
        content_type { 'text/plain' }
      end

      trait :delivered do
        pending_delivery
        message_id { Faker::Number.number(19) }
        preferences do
          {
            delivery_retry:          1,
            twitter:                 {
              recipient_id: recipient.uid,
              sender_id:    sender_id
            },
            links:                   [
              {
                url:    "https://twitter.com/messages/#{recipient.uid}-#{sender_id}",
                target: '_blank',
                name:   'on Twitter'
              }
            ],
            delivery_status_message: nil,
            delivery_status:         'success',
            delivery_status_date:    Time.current
          }
        end
      end
    end
  end
end
