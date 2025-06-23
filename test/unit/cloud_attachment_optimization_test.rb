require File.expand_path('../../test_helper', __FILE__)

class CloudAttachmentOptimizationTest < ActiveSupport::TestCase
  fixtures :projects, :users, :attachments, :issues, :trackers, :issue_statuses, :enabled_modules, :enumerations

  def setup
    User.current = nil
    # Find or create a cloud attachment for testing
    @cloud_attachment = find_cloud_attachment
    skip "No cloud attachments available for testing" unless @cloud_attachment
  end

  def teardown
    User.current = nil
  end

  def test_cloud_diskfile_detection
    assert @cloud_attachment.respond_to?(:cloud_diskfile?), "cloud_diskfile? method should be available"
    assert @cloud_attachment.cloud_diskfile?, "Should detect cloud file correctly"
  end

  def test_direct_download_url_generation
    assert @cloud_attachment.respond_to?(:direct_download_url), "direct_download_url method should be available"
    
    direct_url = @cloud_attachment.direct_download_url
    
    # Should generate URL for configured backends
    backend = @cloud_attachment.storage_backend
    case backend
    when :s3, :gcs, :azure
      # URL generation depends on configuration being present
      config = Redmine::Configuration[backend.to_s]
      if config&.dig('bucket') || config&.dig('container')
        assert_not_nil direct_url, "Should generate direct download URL for #{backend}"
        assert direct_url.start_with?('http'), "Should be a valid URL"
      else
        assert_nil direct_url, "Should return nil when configuration is missing"
      end
    else
      assert_nil direct_url, "Should return nil for non-cloud backends"
    end
  end

  def test_readable_optimization
    # readable? should work without downloading the file
    assert @cloud_attachment.readable?, "Cloud attachment should be readable"
  end

  def test_storage_backend_detection
    backend = @cloud_attachment.storage_backend
    assert [:s3, :gcs, :azure, :local].include?(backend), "Should return valid storage backend"
  end

  def test_cloud_configuration_check
    backend = @cloud_attachment.storage_backend
    
    if backend != :local
      config = @cloud_attachment.send(:cloud_config)
      assert config.is_a?(Hash), "Cloud config should be a hash"
      
      case backend
      when :s3
        assert config.key?('bucket'), "S3 config should have bucket"
      when :gcs
        assert config.key?('bucket'), "GCS config should have bucket"
      when :azure
        assert config.key?('container'), "Azure config should have container"
      end
    end
  end

  def test_cloud_key_generation
    if @cloud_attachment.cloud_diskfile?
      key = @cloud_attachment.send(:cloud_key)
      assert_not_nil key, "Should generate cloud key"
      assert key.is_a?(String), "Cloud key should be string"
      assert key.include?(@cloud_attachment.created_on.strftime('%Y/%m')), "Should include date path"
    end
  end

  def test_cleanup_temp_file
    # Test cleanup method exists and works
    assert @cloud_attachment.respond_to?(:cleanup_temp_file, true), "Should have cleanup_temp_file method"
    assert @cloud_attachment.respond_to?(:cleanup_after_thumbnail, true), "Should have cleanup_after_thumbnail method"
    
    # Should not raise error when called
    assert_nothing_raised do
      @cloud_attachment.send(:cleanup_temp_file)
      @cloud_attachment.send(:cleanup_after_thumbnail)
    end
  end

  # Helper method to enable monitoring for specific tests
  def with_diskfile_monitoring
    monitoring_enabled = false
    
    begin
      # Enable monitoring
      unless Attachment.method_defined?(:original_diskfile_without_monitoring)
        Attachment.class_eval do
          alias_method :original_diskfile_without_monitoring, :diskfile
          
          def diskfile
            if respond_to?(:cloud_diskfile?) && cloud_diskfile?
              Rails.logger.warn "[TEST MONITOR] diskfile() called for cloud attachment #{self.id}"
            end
            original_diskfile_without_monitoring
          end
        end
        monitoring_enabled = true
      end
      
      yield
      
    ensure
      # Cleanup monitoring
      if monitoring_enabled && Attachment.method_defined?(:original_diskfile_without_monitoring)
        Attachment.class_eval do
          alias_method :diskfile, :original_diskfile_without_monitoring
          remove_method :original_diskfile_without_monitoring
        end
      end
    end
  end

  def test_optimization_reduces_diskfile_calls
    skip "Only run this test when ImageMagick is available" unless convert_installed?
    skip "Only test image attachments" unless @cloud_attachment.is_image?
    
    diskfile_call_count = 0
    
    # Monitor diskfile calls
    @cloud_attachment.define_singleton_method(:diskfile) do
      diskfile_call_count += 1
      super()
    end
    
    # Test operations that should be optimized
    @cloud_attachment.readable?
    
    # readable? should not call diskfile for cloud attachments
    assert_equal 0, diskfile_call_count, "readable? should not call diskfile() for cloud attachments"
  end

  private

  def convert_installed?
    Redmine::Thumbnail.convert_available?
  end
end 
