# Rails.logger.info "[CloudAttachmentPro LOAD] Attempting to load AttachmentsControllerPatch file: #{__FILE__}"
module RedmineCloudAttachmentPro
  module Patches
    module AttachmentsControllerPatch
      extend ActiveSupport::Concern

      included do
        # Store the original download method
        alias_method :original_download_for_cloud_pro, :download

        # Override the download method
        def download
          # @attachment is typically set by a before_action like :find_attachment or :file_readable
          # The presigned URL logic below should only apply if the user has rights to view/download the attachment.
          # Basic check for @attachment and respond_to?(:direct_download_url) is done before calling direct_download_url.

          presigned_url_value = @attachment.direct_download_url if @attachment&.respond_to?(:direct_download_url)

          if presigned_url_value
            begin
              redirect_to presigned_url_value, allow_other_host: true
              return # Crucial to prevent original_download_for_cloud_pro from executing
            rescue => e
              Rails.logger.error "[CloudAttachmentPro] Error during presigned URL redirect for attachment ##{@attachment&.id}: #{e.message}. Falling back to normal download."
              # Fall through to original_download_for_cloud_pro
            end
          end

          # If no presigned URL, or an error occurred, or attachment doesn't support it,
          # or if the @attachment conditions were not met, call original download method.
          original_download_for_cloud_pro
        end
      end
    end
  end
end 
