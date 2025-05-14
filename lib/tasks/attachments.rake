namespace :attachments do
  desc 'Prefix disk_filename with cloud storage identifier (s3_, gcs_, azure_) if missing'
  task prefix_cloud_filenames: :environment do
    storage = Redmine::Configuration['storage'].to_s
    prefix = case storage
             when 's3', 'gcs', 'azure'
               "#{storage}_"
             else
               nil
             end

    unless prefix
      puts "❌ Unsupported or missing storage backend: #{storage.inspect}"
      exit 1
    end

    puts "🔍 Updating attachments for storage: #{storage}..."

    updated = 0

    Attachment.find_each do |attachment|
      next unless attachment.disk_filename.present?
      next if attachment.disk_filename.start_with?(prefix)

      # Avoid double-prefixing if already prefixed with another cloud type
      next if attachment.disk_filename.match?(/^(s3|gcs|azure)_/)

      new_filename = "#{prefix}#{attachment.disk_filename}"

      attachment.update_column(:disk_filename, new_filename)
      puts "✅ Updated ##{attachment.id} to #{new_filename}"
      updated += 1
    end

    puts "🎉 Done. Total attachments updated: #{updated}"
  end
end
