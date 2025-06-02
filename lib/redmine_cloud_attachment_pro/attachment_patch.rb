require 'aws-sdk-s3'
require 'google/cloud/storage'
# require 'azure/storage/blob' # Commented out to avoid dependency conflict if Azure is not used
require_dependency 'attachment'

module RedmineCloudAttachmentPro
  module AttachmentPatch
    def self.included(base)
      base.class_eval do
        after_destroy :delete_from_cloud

        # Method to generate a direct download URL (e.g., S3 presigned URL)
        # Returns the presigned URL if available, otherwise nil.
        def direct_download_url(expires_in = 15.minutes)
          return s3_presigned_url(expires_in) if storage_backend == :s3 && cloud_diskfile?
          nil
        end

        def storage_backend
          Redmine::Configuration["storage"]&.to_sym || :local
        end

        def files_to_final_location
          return unless @temp_file

          sha = Digest::SHA256.new
          content = read_temp_file(@temp_file, sha)
          self.disk_directory = target_directory

          upload_content(content)

          self.digest = sha.hexdigest
          @temp_file = nil

          set_content_type
        end

        def diskfile
          return local_diskfile unless cloud_diskfile?

          # Path to the cache directory for cloud attachments
          cloud_cache_base_dir = Rails.root.join('tmp', 'redmine_cloud_attachment_pro_cache')
          Rails.logger.info "[CloudAttachmentPro Debug] cloud_cache_base_dir: #{cloud_cache_base_dir.to_s}"

          # Ensure self.id and self.disk_filename are available and valid
          # self.id should always be there for a saved record.
          # self.disk_filename is the unique filename on disk.
          unless self.id && self.disk_filename.present?
            Rails.logger.error("[CloudAttachmentPro] Attachment ID or disk_filename missing for attachment: #{self.inspect}")
            return local_diskfile # Fallback
          end
          
          target_dir = File.join(cloud_cache_base_dir, self.id.to_s)
          cached_file_path = File.join(target_dir, self.disk_filename)

          # Check if the cached file exists and is not empty
          if File.exist?(cached_file_path) && File.size?(cached_file_path).to_i > 0
            Rails.logger.debug { "[CloudAttachmentPro] Serving attachment #{self.id} from cache: #{cached_file_path}" }
            return cached_file_path
          elsif File.exist?(cached_file_path) # Exists but is empty
             Rails.logger.warn { "[CloudAttachmentPro] Found empty cached file for attachment #{self.id}. Will attempt re-download. Path: #{cached_file_path}" }
             # Attempt to remove the empty or corrupted file before re-downloading
             begin
               FileUtils.rm_f(cached_file_path)
             rescue SystemCallError => e # Catch potential errors during file deletion
               Rails.logger.error("[CloudAttachmentPro] Failed to remove empty/corrupted cached file #{cached_file_path}: #{e.message}")
               # If removal fails, it might be problematic, but proceed to attempt download anyway or fallback.
               # For now, we'll log and let the download attempt proceed, which might overwrite or fail.
             end
          end

          Rails.logger.info { "[CloudAttachmentPro] Attempting to download attachment #{self.id} to cache: #{cached_file_path}" }
          begin
            # Ensure the target directory exists
            FileUtils.mkdir_p(target_dir) unless Dir.exist?(target_dir)
            
            # Download the file to the cache path
            File.open(cached_file_path, 'wb') do |f|
              # download_from_cloud is expected to write to the IO object 'f'
              download_from_cloud(f)
            end
            
            # Verify that the download was successful and the file is not empty
            unless File.size?(cached_file_path).to_i > 0
              Rails.logger.error("[CloudAttachmentPro] Cloud download resulted in an empty file for attachment #{self.id}. Path: #{cached_file_path}")
              # Clean up the empty file
              FileUtils.rm_f(cached_file_path) if File.exist?(cached_file_path)
              return local_diskfile # Fallback to local diskfile
            end

            Rails.logger.info { "[CloudAttachmentPro] Successfully downloaded attachment #{self.id} to cache: #{cached_file_path}" }
            return cached_file_path
          rescue => e
            Rails.logger.error("[CloudAttachmentPro] Error during cloud download or file operations for attachment #{self.id} to #{cached_file_path}: #{e.message}\nBacktrace:\n#{e.backtrace.join("\n")}")
            # Clean up any potentially corrupted or partial file created during a failed download
            FileUtils.rm_f(cached_file_path) if File.exist?(cached_file_path)
            return local_diskfile # Fallback to local diskfile
          end
        end

        def delete_from_cloud
          return unless cloud_diskfile?

          begin
            delete_from_backend(cloud_key)
          rescue => e
            Rails.logger.error("[CloudAttachmentPro] Failed to delete #{cloud_key} from cloud for attachment #{self.id}: #{e.message}")
          end
        end

        private

        def upload_content(content)
          key = cloud_key

          case storage_backend
          when :s3
            s3_client.put_object(bucket: s3_bucket, key: key, body: content)
          when :gcs
            gcs_bucket.create_file(StringIO.new(content), key)
          when :azure
            azure_blob_client.create_block_blob(azure_container, key, content)
          else
            save_locally(content)
            return
          end

          self.disk_filename = "#{storage_backend}_#{File.basename(key)}"
        end

        def download_from_cloud(tmp)
          case storage_backend
          when :s3
            s3_client.get_object(bucket: s3_bucket, key: cloud_key) { |chunk| tmp.write(chunk) }
          when :gcs
            gcs_bucket.file(cloud_key)&.download(tmp.path)
          when :azure
            _, content = azure_blob_client.get_blob(azure_container, cloud_key)
            tmp.write(content)
          end
        end

        def delete_from_backend(key)
          case storage_backend
          when :s3
            s3_client.delete_object(bucket: s3_bucket, key: key)
          when :gcs
            gcs_bucket.file(key)&.delete
          when :azure
            azure_blob_client.delete_blob(azure_container, key)
          end
        end

        def save_locally(content)
          Attachment.create_diskfile(filename, disk_directory) do |f|
            self.disk_filename = File.basename(f.path)
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

        def cloud_filename
          disk_filename.presence || "#{SecureRandom.hex}_#{filename}"
        end

        def cloud_key
          prefix = "#{storage_backend}_"
          key = File.join(cloud_base_path, created_on.strftime('%Y/%m'), cloud_filename)
          cloud_diskfile? ? key.sub(/#{prefix}/, '') : key
        end

        def local_diskfile
          File.join(self.class.storage_path, disk_directory.to_s, disk_filename.to_s)
        end

        def cloud_diskfile?
          disk_filename.to_s.match?(/^(s3|gcs|azure)_[^_]+_/)
        end

        def cloud_config
          Redmine::Configuration[storage_backend.to_s] || {}
        end

        def cloud_base_path
          cloud_config['path'] || 'redmine/files'
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

        def s3_presigned_url(expires_in = 15.minutes)
          unless storage_backend == :s3 && cloud_config['bucket'].present?
            return nil
          end

          begin
            signer = Aws::S3::Presigner.new(client: s3_client)
            url = signer.presigned_url(:get_object, bucket: s3_bucket, key: cloud_key, expires_in: expires_in.to_i)
            url
          rescue => e
            Rails.logger.error("[CloudAttachmentPro] Failed to generate S3 presigned URL for #{cloud_key} (attachment #{self.id}): #{e.message}")
            nil
          end
        end
      end
    end
  end
end

# Ensure the patch is applied only once
Attachment.include RedmineCloudAttachmentPro::AttachmentPatch unless Attachment.included_modules.include?(RedmineCloudAttachmentPro::AttachmentPatch)
