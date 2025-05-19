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
          # Rails.logger.info "[CloudAttachmentPro DEBUG] In Patched AttachmentsController#download for attachment_id: #{@attachment&.id}"
          # @attachment is typically set by a before_action like :find_attachment or :file_readable
          if @attachment && @attachment.respond_to?(:direct_download_url) && @attachment.container.is_a?(Project) && !@attachment.container.is_public? && !User.current.admin?
            # Check project-specific permission for downloading attachments if project is not public and user is not admin
            # You might need to define a specific permission like :download_s3_attachments
            # or rely on existing ones like :view_issues if applicable.
            # This is a placeholder for fine-grained permission check.
            # For now, we assume if they can see the attachment record, they can download via presigned URL.
            # The original #download has its own permission checks (e.g. @attachment.readable?)
            # which should still be respected or replicated if bypassed too early.

            # If #file_readable or similar before_action did not run or run differently due to prepend,
            # ensure @attachment is readable by User.current
            # return deny_access unless @attachment.readable?(User.current) # Example check

          end

          # Attempt to get a presigned URL
          presigned_url_value = @attachment.direct_download_url if @attachment && @attachment.respond_to?(:direct_download_url)
          # Rails.logger.info "[CloudAttachmentPro DEBUG] Value from @attachment.direct_download_url: #{presigned_url_value.inspect}"

          if presigned_url_value
            # Rails.logger.info "[CloudAttachmentPro DEBUG] Presigned URL is present. Attempting redirect for Attachment ID: #{@attachment.id}"
            begin
              # Rails.logger.info "[CloudAttachmentPro] Redirecting to S3 presigned URL for attachment ##{@attachment.id}"
              redirect_to presigned_url_value, allow_other_host: true
              return # Crucial to prevent original_download_for_cloud_pro from executing
            rescue => e
              Rails.logger.error "[CloudAttachmentPro] Error during presigned URL redirect: #{e.message}. Falling back to normal download."
              # Fall through to original_download_for_cloud_pro
            end
          # else
            # Rails.logger.info "[CloudAttachmentPro DEBUG] Presigned URL is nil or blank. Falling back to original download for attachment_id: #{@attachment&.id}"
          end

          # If no presigned URL, or an error occurred, or attachment doesn't support it, call original download method.
          original_download_for_cloud_pro
        end
      end
    end
  end
end 
