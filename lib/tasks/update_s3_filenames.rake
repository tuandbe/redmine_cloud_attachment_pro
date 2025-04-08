namespace :attachments do
  desc 'Prefix disk_filename with s3_ for attachments stored in S3'
  task prefix_s3_filenames: :environment do
    puts "Updating attachments with S3 prefix..."

    updated = 0
    Attachment.find_each do |attachment|
      next unless attachment.disk_filename.present?

      # Skip if already prefixed or not stored in S3
      next if attachment.disk_filename.start_with?("s3_")
      next unless Redmine::Configuration["storage"].to_s == "s3"

      attachment.update_column(:disk_filename, "s3_#{attachment.disk_filename}")
      updated += 1
    end

    puts "✅ Updated #{updated} attachment(s) with 's3_' prefix."
  end
end