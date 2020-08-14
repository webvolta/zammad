class Issue3110ServiceNowProvider < ActiveRecord::Migration[5.2]
  def change

    # return if it's a new setup
    return if !Setting.exists?(name: 'system_init_done')

    ExternalSync.where(source: 'ServiceNow').find_each do |row|
      article = Ticket.find(row.o_id).articles.first
      source_name = Channel::Filter::ServiceNowCheck.source_name(from: article.from)
      row.update(source: source_name)
    end
  end
end
