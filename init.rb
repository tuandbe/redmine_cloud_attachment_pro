require 'redmine'
require_dependency 'redmine/plugin'
# Do not require patches directly here if using to_prepare for loading
# require_relative 'lib/redmine_cloud_attachment_pro/attachment_patch'

# Rails.logger.info "[CloudAttachmentPro INIT] Registering plugin: redmine_cloud_attachment_pro. File: #{__FILE__}"

Redmine::Plugin.register :redmine_cloud_attachment_pro do
  name 'Redmine Cloud Attachment Pro'
  author 'Railsfactory & TuannNDE (modified for S3 Presigned URL)'
  description 'A plugin for Redmine that enables storing attachments in multiple cloud backends with S3 presigned URL support.'
  version '1.1.1' # Incremented version
  url 'https://github.com/railsfactory-sivamanikandan/redmine_cloud_attachment_pro'
  author_url 'https://github.com/tuannde'

  # Rails.logger.info "[CloudAttachmentPro INIT] Inside plugin registration block."

  # Plugin settings definition (if any)
  # settings default: { 'setting_key' => 'default_value' }, partial: 'settings/rcap_settings'

  # Rails.logger.info "[CloudAttachmentPro INIT] Attempting to load and apply patches directly."

  # Ensure Attachment class is loaded before patching
  begin
    require_dependency 'attachment' # Core Redmine class
    patch_module_fqn = 'RedmineCloudAttachmentPro::AttachmentPatch'
    patch_file_path = File.join(File.dirname(__FILE__), 'lib', 'redmine_cloud_attachment_pro', 'attachment_patch.rb')
    # Rails.logger.info "[CloudAttachmentPro INIT] Requiring AttachmentPatch from: #{patch_file_path}"
    require_dependency patch_file_path
    # Rails.logger.info "[CloudAttachmentPro INIT] Successfully required AttachmentPatch."

    patch_module = patch_module_fqn.constantize
    target_class = Attachment

    unless target_class.included_modules.include?(patch_module)
      target_class.send(:include, patch_module)
      # Rails.logger.info "[CloudAttachmentPro INIT] Successfully patched Attachment model with #{patch_module_fqn}."
    # else
      # Rails.logger.info "[CloudAttachmentPro INIT] Attachment model already includes #{patch_module_fqn}."
    end
  rescue LoadError => e
    Rails.logger.error "[CloudAttachmentPro] Error loading/applying AttachmentPatch. Message: #{e.message}"
  rescue NameError => e
    Rails.logger.error "[CloudAttachmentPro] Error finding Attachment or AttachmentPatch module. Message: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[CloudAttachmentPro] General error applying AttachmentPatch. Message: #{e.message}"
  end

  # Ensure AttachmentsController is loaded before patching
  begin
    require_dependency 'attachments_controller' # Core Redmine class
    controller_patch_fqn = 'RedmineCloudAttachmentPro::Patches::AttachmentsControllerPatch'
    controller_patch_path = File.join(File.dirname(__FILE__), 'lib', 'redmine_cloud_attachment_pro', 'patches', 'attachments_controller_patch.rb')
    # Rails.logger.info "[CloudAttachmentPro INIT] Requiring AttachmentsControllerPatch from: #{controller_patch_path}"
    require_dependency controller_patch_path
    # Rails.logger.info "[CloudAttachmentPro INIT] Successfully required AttachmentsControllerPatch."

    patch_module = controller_patch_fqn.constantize
    target_controller = AttachmentsController

    unless target_controller.included_modules.include?(patch_module)
      target_controller.send(:include, patch_module) # Using include, ensure patch uses `included do` or `prepended do` as appropriate
      # Rails.logger.info "[CloudAttachmentPro INIT] Successfully patched AttachmentsController with #{controller_patch_fqn}."
    # else
      # Rails.logger.info "[CloudAttachmentPro INIT] AttachmentsController already includes #{controller_patch_fqn}."
    end
  rescue LoadError => e
    Rails.logger.error "[CloudAttachmentPro] Error loading/applying AttachmentsControllerPatch. Message: #{e.message}"
  rescue NameError => e
    Rails.logger.error "[CloudAttachmentPro] Error finding AttachmentsController or its patch module. Message: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[CloudAttachmentPro] General error applying AttachmentsControllerPatch. Message: #{e.message}"
  end

  # Ensure AttachmentsHelper is loaded before patching
  begin
    require_dependency 'attachments_helper' # Core Redmine helper
    helper_patch_fqn = 'RedmineCloudAttachmentPro::Patches::AttachmentsHelperPatch'
    helper_patch_path = File.join(File.dirname(__FILE__), 'lib', 'redmine_cloud_attachment_pro', 'patches', 'attachments_helper_patch.rb')
    require_dependency helper_patch_path

    patch_module = helper_patch_fqn.constantize
    target_helper = AttachmentsHelper

    unless target_helper.included_modules.include?(patch_module)
      target_helper.send(:include, patch_module)
      Rails.logger.debug "[CloudAttachmentPro] Successfully patched AttachmentsHelper with #{helper_patch_fqn}."
    end

    # Also patch ApplicationHelper for thumbnail_path method
    ApplicationHelper.send(:include, patch_module) unless ApplicationHelper.included_modules.include?(patch_module)
  rescue LoadError => e
    Rails.logger.error "[CloudAttachmentPro] Error loading/applying AttachmentsHelperPatch. Message: #{e.message}"
  rescue NameError => e
    Rails.logger.error "[CloudAttachmentPro] Error finding AttachmentsHelper or its patch module. Message: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[CloudAttachmentPro] General error applying AttachmentsHelperPatch. Message: #{e.message}"
  end

  # Note: optimization_test.rb moved to test/ directory

  # Rails.logger.info "[CloudAttachmentPro INIT] Exiting plugin registration block after attempting direct patch loading."
end
