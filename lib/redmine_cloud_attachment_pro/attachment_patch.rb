require 'aws-sdk-s3'
require 'google/cloud/storage'
require 'azure/storage/blob'
require_dependency 'attachment'

module RedmineCloudAttachmentPro
  module AttachmentPatch
    def self.included(base)
      base.class_eval do
        after_destroy :delete_from_cloud

        def storage_backend
          Redmine::Configuration["storage"]&.to_sym || :local
        end

        def files_to_final_location
          return unless @temp_file

          sha = Digest::SHA256.new
          content = read_temp_file(@temp_file, sha)
          self.disk_directory = target_directory

          case storage_backend
          when :s3
            upload_to_s3(content)
          when :gcs
            upload_to_gcs(content)
          when :azure
            upload_to_azure(content)
          else
            save_locally(content)
          end

          self.digest = sha.hexdigest
          @temp_file = nil

          set_content_type
        end

        def diskfile
          return local_diskfile unless disk_filename.to_s.start_with?("s3_") || disk_filename.to_s.start_with?("gcs_") || disk_filename.to_s.start_with?("azure_")

          begin
            prefix = disk_filename.split('_').first + '_'
            key = File.join(cloud_base_path, disk_directory.to_s, disk_filename.sub(prefix, ""))

            tmp = Tempfile.new(["redmine", File.extname(key)])
            tmp.binmode

            case storage_backend
            when :s3
              s3_client.get_object(bucket: s3_bucket, key: key) { |chunk| tmp.write(chunk) }
            when :gcs
              file = gcs_bucket.file(key)
              file.download(tmp.path) if file
            when :azure
              blob, content = azure_blob_client.get_blob(azure_container, key)
              tmp.write(content)
            end

            tmp.rewind
            tmp.path
          rescue => e
            Rails.logger.error("[CloudAttachmentPro] Fallback to local: #{e.message}")
            local_diskfile
          end
        end

        def delete_from_cloud
          return unless disk_filename.to_s =~ /^(s3|gcs|azure)_/

          prefix = disk_filename.split('_').first + '_'
          key = File.join(cloud_base_path, disk_directory.to_s, disk_filename.sub(prefix, ""))

          begin
            case storage_backend
            when :s3
              s3_client.delete_object(bucket: s3_bucket, key: key)
              Rails.logger.info("[S3] Deleted #{key}")
            when :gcs
              file = gcs_bucket.file(key)
              file&.delete
              Rails.logger.info("[GCS] Deleted #{key}")
            when :azure
              azure_blob_client.delete_blob(azure_container, key)
              Rails.logger.info("[Azure] Deleted #{key}")
            end
          rescue => e
            Rails.logger.error("[CloudAttachmentPro] Failed to delete #{key}: #{e.message}")
          end
        end

        private

        def upload_to_s3(content)
          filename = disk_filename.presence || "#{SecureRandom.hex}_#{self.filename}"
          key = File.join(cloud_base_path, created_on.strftime('%Y/%m'), filename)
          s3_client.put_object(bucket: s3_bucket, key: key, body: content)
          self.disk_filename = "s3_#{File.basename(key)}"
        end

        def upload_to_gcs(content)
          filename = disk_filename.presence || "#{SecureRandom.hex}_#{self.filename}"
          key = File.join(cloud_base_path, created_on.strftime('%Y/%m'), filename)
          gcs_bucket.create_file(StringIO.new(content), key)
          self.disk_filename = "gcs_#{File.basename(key)}"
        end

        def upload_to_azure(content)
          filename = disk_filename.presence || "#{SecureRandom.hex}_#{self.filename}"
          key = File.join(cloud_base_path, created_on.strftime('%Y/%m'), filename)
          azure_blob_client.create_block_blob(azure_container, key, content)
          self.disk_filename = "azure_#{File.basename(key)}"
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
          content = temp_file.respond_to?(:read) ? temp_file.tap(&:rewind).read : temp_file.to_s
          sha.update(content)
          content
        end

        def local_diskfile
          File.join(self.class.storage_path, disk_directory.to_s, disk_filename.to_s)
        end

        def s3_client
          @s3_client ||= Aws::S3::Client.new(
            access_key_id: cloud_config['access_key_id'],
            secret_access_key: cloud_config['secret_access_key'],
            region: cloud_config['region']
          )
        end

        def s3_bucket
          cloud_config['bucket']
        end

        def gcs_client
          @gcs_client ||= Google::Cloud::Storage.new(
            project_id: cloud_config['project_id'],
            credentials: cloud_config['gcs_credentials']
          )
        end

        def gcs_bucket
          @gcs_bucket ||= gcs_client.bucket(cloud_config['bucket'])
        end

        def azure_blob_client
          @azure_blob_client ||= Azure::Storage::Blob::BlobService.create(
            storage_account_name: cloud_config['account_name'],
            storage_access_key: cloud_config['access_key']
          )
        end

        def azure_container
          cloud_config['container']
        end

        def cloud_base_path
          cloud_config['path'] || 'redmine/files'
        end

        def cloud_config
          Redmine::Configuration[storage_backend.to_s] || {}
        end
      end
    end
  end
end

Attachment.include RedmineCloudAttachmentPro::AttachmentPatch unless Attachment.included_modules.include?(RedmineCloudAttachmentPro::AttachmentPatch)