class ImapAuthenticationMigrationCleanupJob < ApplicationJob
  include HasActiveJobLock

  def perform
    Channel.where(area: 'Google::Account').find_each do |channel|
      next if channel.options.blank?
      next if channel.options[:backup_imap_classic].blank?
      next if channel.options[:backup_imap_classic][:migrated_at] > 7.days.ago

      channel.options.delete(:backup_imap_classic)
      channel.save!
    end
  end
end
