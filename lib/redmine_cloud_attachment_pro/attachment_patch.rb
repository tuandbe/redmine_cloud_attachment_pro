require 'aws-sdk-s3'
require_dependency 'attachment'

module RedmineCloudAttachmentPro
  module AttachmentPatch
    def self.included(base)
      base.class_eval do
        after_destroy :delete_from_s3

        def storage_backend
          Redmine::Configuration['storage'].to_s == 's3' ? :s3 : :local
        end

        def files_to_final_location
          return unless @temp_file

          sha = Digest::SHA256.new
          content = read_temp_file(@temp_file, sha)
          self.disk_directory = target_directory
          if storage_backend == :s3
            upload_to_s3(content)
          else
            save_locally(content)
          end

          self.digest = sha.hexdigest
          @temp_file = nil

          set_content_type
        end

        def diskfile
          return local_diskfile unless disk_filename.to_s.start_with?("s3_")

          begin
            s3_key = File.join(s3_base_path, disk_directory.to_s, disk_filename.sub("s3_", ""))
            tmp = Tempfile.new(["redmine", File.extname(s3_key)])
            tmp.binmode

            s3_client.get_object(bucket: s3_bucket, key: s3_key) do |chunk|
              tmp.write(chunk)
            end

            tmp.rewind
            tmp.path
          rescue Aws::S3::Errors::NoSuchKey => e
            Rails.logger.error("[S3] Key not found: #{e.message}")
            local_diskfile
          rescue => e
            Rails.logger.error("[S3] Unexpected error in diskfile: #{e.message}")
            local_diskfile
          end
        end

        def delete_from_s3
          return unless disk_filename.to_s.start_with?("s3_")

          s3_key = File.join(s3_base_path, disk_directory.to_s, disk_filename.sub("s3_", ""))
          s3_client.delete_object(bucket: s3_bucket, key: s3_key)
          Rails.logger.info("[S3] Deleted #{s3_key}")
        rescue Aws::S3::Errors::ServiceError => e
          Rails.logger.error("[S3] Failed to delete #{s3_key}: #{e.message}")
        end

        private

        def upload_to_s3(content)
          filename_for_s3 = disk_filename.presence || "#{SecureRandom.hex}_#{filename}"
          s3_key = File.join(s3_base_path, created_on.strftime('%Y/%m'), filename_for_s3)

          s3_client.put_object(bucket: s3_bucket, key: s3_key, body: content)

          self.disk_filename = "s3_#{File.basename(s3_key)}"
        end

        def save_locally(content)
          Attachment.create_diskfile(filename, disk_directory) do |f|
            self.disk_filename = File.basename f.path
            f.write(content)
          end
        end

        def set_content_type
          if content_type.blank? && filename.present?
            self.content_type = Redmine::MimeType.of(filename)
          end

          self.content_type = nil if content_type&.length.to_i > 255
        end

        def read_temp_file(temp_file, sha)
          if temp_file.respond_to?(:read)
            temp_file.rewind
            content = temp_file.read
          else
            content = temp_file.to_s
          end
          sha.update(content)
          content
        end

        def local_diskfile
          File.join(self.class.storage_path, disk_directory.to_s, disk_filename.to_s)
        end

        def s3_client
          @s3_client ||= Aws::S3::Client.new(
            access_key_id: s3_config['access_key_id'],
            secret_access_key: s3_config['secret_access_key'],
            region: s3_config['region']
          )
        end

        def s3_bucket
          s3_config['bucket']
        end

        def s3_base_path
          s3_config['path'] || 'redmine/files'
        end

        def s3_config
          Redmine::Configuration['s3'] || {}
        end
      end
    end
  end
end

Rails.configuration.to_prepare do
  Attachment.include RedmineCloudAttachmentPro::AttachmentPatch unless Attachment.included_modules.include?(RedmineCloudAttachmentPro::AttachmentPatch)
end