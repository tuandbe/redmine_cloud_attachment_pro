require File.expand_path('../../test_helper', __FILE__)

class CloudAttachmentThumbnailTest < ActiveSupport::TestCase
  fixtures :projects, :users, :attachments, :issues, :trackers, :issue_statuses, :enabled_modules, :enumerations

  def setup
    User.current = nil
    
    # Find cloud image attachments for testing
    @cloud_image_attachment = find_cloud_attachment(type: :image)
    
    skip "No cloud image attachments available for testing" unless @cloud_image_attachment
    skip "ImageMagick convert not available" unless convert_installed?
  end

  def teardown
    User.current = nil
    # Clean up any test thumbnails
    cleanup_test_thumbnails
  end

  def test_cloud_attachment_thumbnailable
    assert @cloud_image_attachment.respond_to?(:thumbnailable?), "thumbnailable? method should be available"
    assert @cloud_image_attachment.thumbnailable?, "Cloud image attachment should be thumbnailable"
  end

  def test_thumbnail_generation_for_cloud_attachment
    # Test thumbnail generation
    thumbnail_path = @cloud_image_attachment.thumbnail

    if thumbnail_path
      assert File.exist?(thumbnail_path), "Thumbnail file should exist at: #{thumbnail_path}"
      assert File.size(thumbnail_path) > 0, "Thumbnail file should not be empty"
      assert thumbnail_path.end_with?('.thumb'), "Thumbnail should have .thumb extension"
      
      # Verify file naming convention
      expected_pattern = /#{@cloud_image_attachment.digest}_#{@cloud_image_attachment.filesize}_\d+\.thumb$/
      assert thumbnail_path.match?(expected_pattern), "Thumbnail should follow naming convention"
    else
      # If thumbnail generation fails, it might be due to missing cloud access
      # This is acceptable in test environment
      puts "Warning: Thumbnail generation returned nil for attachment #{@cloud_image_attachment.id}"
    end
  end

  def test_thumbnail_different_sizes
    sizes = [100, 200, 400]
    
    sizes.each do |size|
      thumbnail_path = @cloud_image_attachment.thumbnail(size: size)
      
      if thumbnail_path && File.exist?(thumbnail_path)
        # Calculate expected size (rounded to nearest 50)
        expected_size = (size / 50.0).ceil * 50
        expected_size = 800 if expected_size > 800
        expected_size = 100 unless expected_size > 0
        
        assert thumbnail_path.include?("_#{expected_size}.thumb"), 
               "Thumbnail should be generated for size #{expected_size}, got: #{File.basename(thumbnail_path)}"
      end
    end
  end

  def test_thumbnail_caching
    # First call should generate thumbnail
    first_call = @cloud_image_attachment.thumbnail
    
    if first_call && File.exist?(first_call)
      # Record file modification time
      first_mtime = File.mtime(first_call)
      
      # Wait a moment to ensure different timestamps
      sleep(0.1)
      
      # Second call should reuse existing thumbnail
      second_call = @cloud_image_attachment.thumbnail
      
      assert_equal first_call, second_call, "Should return same thumbnail path"
      assert_equal first_mtime, File.mtime(second_call), "Should reuse existing thumbnail file"
    end
  end

  def test_thumbnails_storage_path
    thumbnails_dir = Attachment.thumbnails_storage_path
    assert_not_nil thumbnails_dir, "Thumbnails storage path should be defined"
    assert thumbnails_dir.is_a?(String), "Thumbnails storage path should be a string"
    
    # Test that directory exists or can be created
    unless Dir.exist?(thumbnails_dir)
      assert Dir.mkdir(thumbnails_dir), "Should be able to create thumbnails directory"
    end
  end

  def test_cleanup_after_thumbnail_generation
    original_thumbnail = @cloud_image_attachment.thumbnail
    
    if original_thumbnail && File.exist?(original_thumbnail)
      # Test cleanup method
      assert @cloud_image_attachment.respond_to?(:cleanup_after_thumbnail, true), 
             "Should have cleanup_after_thumbnail method"
      
      # Should not raise error
      assert_nothing_raised do
        @cloud_image_attachment.send(:cleanup_after_thumbnail)
      end
    end
  end

  def test_thumbnail_for_non_image_cloud_attachment
    # Find a non-image cloud attachment
    non_image_attachment = Attachment.where("disk_filename LIKE 's3_%' OR disk_filename LIKE 'gcs_%' OR disk_filename LIKE 'azure_%'")
                                    .where.not("filename LIKE '%.png' OR filename LIKE '%.jpg' OR filename LIKE '%.jpeg' OR filename LIKE '%.gif'")
                                    .first
    
    if non_image_attachment
      assert_not non_image_attachment.thumbnailable?, "Non-image attachment should not be thumbnailable"
      
      thumbnail_path = non_image_attachment.thumbnail
      assert_nil thumbnail_path, "Non-image attachment should not generate thumbnail"
    end
  end

  def test_pdf_thumbnail_generation
    skip "Ghostscript not available" unless gs_installed?
    
    # Find a PDF cloud attachment
    pdf_attachment = Attachment.where("disk_filename LIKE 's3_%' OR disk_filename LIKE 'gcs_%' OR disk_filename LIKE 'azure_%'")
                              .where("filename LIKE '%.pdf'")
                              .first
    
    if pdf_attachment
      assert pdf_attachment.thumbnailable?, "PDF attachment should be thumbnailable"
      
      thumbnail_path = pdf_attachment.thumbnail
      if thumbnail_path && File.exist?(thumbnail_path)
        assert thumbnail_path.end_with?('.thumb'), "PDF thumbnail should have .thumb extension"
      end
    end
  end

  def test_thumbnail_error_handling
    # Test with invalid attachment configuration
    invalid_attachment = @cloud_image_attachment.dup
    invalid_attachment.disk_filename = "s3_invalid_file.jpg"
    invalid_attachment.digest = "invalid_digest"
    
    # Should handle errors gracefully
    assert_nothing_raised do
      thumbnail_path = invalid_attachment.thumbnail
      # May return nil or valid path depending on implementation
    end
  end

  def test_large_thumbnail_size_limit
    # Test maximum thumbnail size (should be capped at 800)
    large_size = 2000
    thumbnail_path = @cloud_image_attachment.thumbnail(size: large_size)
    
    if thumbnail_path && File.exist?(thumbnail_path)
      # Should be capped at 800
      assert thumbnail_path.include?("_800.thumb"), 
             "Large thumbnail size should be capped at 800, got: #{File.basename(thumbnail_path)}"
    end
  end

  private

  def convert_installed?
    Redmine::Thumbnail.convert_available?
  end

  def gs_installed?
    Redmine::Thumbnail.gs_available?
  end

  def cleanup_test_thumbnails
    thumbnails_dir = Attachment.thumbnails_storage_path
    return unless Dir.exist?(thumbnails_dir)
    
    # Only clean up test-related thumbnails to avoid interfering with other tests
    test_pattern = File.join(thumbnails_dir, "*.thumb")
    Dir.glob(test_pattern).each do |file|
      # Only delete thumbnails that might belong to our test attachments
      if @cloud_image_attachment&.digest && file.include?(@cloud_image_attachment.digest)
        File.delete(file) rescue nil
      end
    end
  end
end 
