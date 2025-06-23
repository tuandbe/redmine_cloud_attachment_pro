require File.expand_path('../../test_helper', __FILE__)

class CloudAttachmentIntegrationTest < Redmine::IntegrationTest
  fixtures :projects, :users, :attachments, :issues, :roles, :members, :member_roles, 
           :trackers, :issue_statuses, :enabled_modules, :enumerations

  def setup
    @user = User.find(2) # jsmith 
    @project = Project.find(1)
    @cloud_attachment = find_cloud_attachment
    skip "No cloud attachments available for testing" unless @cloud_attachment
  end

  def test_cloud_attachment_download_redirect
    log_user('jsmith', 'jsmith')
    
    # Test direct download for cloud attachments
    get "/attachments/download/#{@cloud_attachment.id}/#{@cloud_attachment.filename}"
    
    # Should either redirect to cloud URL or serve file directly
    assert_response_in [200, 302], "Should handle cloud attachment download"
    
    if response.status == 302
      # Should redirect to cloud storage URL
      assert response.location.present?, "Should redirect to cloud storage URL"
      assert response.location.start_with?('http'), "Redirect location should be a URL"
    end
  end

  def test_cloud_attachment_show_view
    log_user('jsmith', 'jsmith')
    
    # Test show view for cloud attachments
    get "/attachments/#{@cloud_attachment.id}"
    
    assert_response :success
    assert_select 'h2', text: @cloud_attachment.filename
  end

  def test_thumbnail_generation_via_controller
    skip "ImageMagick convert not available" unless convert_installed?
    skip "Only test image attachments" unless @cloud_attachment.is_image?
    
    log_user('jsmith', 'jsmith')
    
    # Test thumbnail generation through controller
    get "/attachments/thumbnail/#{@cloud_attachment.id}"
    
    # Should either return thumbnail or 404 if generation fails
    assert_response_in [200, 404], "Should handle thumbnail request"
    
    if response.status == 200
      assert_equal 'image/png', response.content_type, "Thumbnail should be PNG format"
      assert response.body.present?, "Thumbnail content should be present"
    end
  end

  def test_api_with_cloud_attachments
    # Test API response includes direct download URLs
    get "/attachments/#{@cloud_attachment.id}.xml", 
        headers: { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials('jsmith', 'jsmith') }
    
    assert_response :success
    assert_equal 'application/xml', response.content_type
    
    # Check if direct_content_url is included for cloud attachments
    assert_select 'attachment content_url', count: 1
  end

  def test_bulk_download_with_cloud_attachments
    skip "Need container with multiple attachments" unless @cloud_attachment.container&.attachments&.count.to_i > 1
    
    log_user('jsmith', 'jsmith')
    
    container = @cloud_attachment.container
    case container
    when Issue
      get "/issues/#{container.id}/attachments/download"
    when Project
      get "/projects/#{container.identifier}/files/download"
    else
      skip "Unsupported container type for bulk download"
    end
    
    # Should handle bulk download with cloud attachments
    assert_response_in [200, 404], "Should handle bulk download"
  end

  def test_cloud_attachment_in_issue_view
    skip "Attachment not associated with issue" unless @cloud_attachment.container.is_a?(Issue)
    
    log_user('jsmith', 'jsmith')
    issue = @cloud_attachment.container
    
    get "/issues/#{issue.id}"
    assert_response :success
    
    # Should display cloud attachment in issue view
    assert_select '.attachments', count: 1
    assert_select 'a', text: @cloud_attachment.filename
  end

  def test_thumbnail_macro_with_cloud_attachments
    skip "ImageMagick convert not available" unless convert_installed?
    skip "Only test image attachments" unless @cloud_attachment.is_image?
    skip "Attachment not associated with issue" unless @cloud_attachment.container.is_a?(Issue)
    
    log_user('jsmith', 'jsmith')
    issue = @cloud_attachment.container
    
    # Add wiki content with thumbnail macro
    wiki_content = "{{thumbnail(#{@cloud_attachment.filename})}}"
    
    put "/issues/#{issue.id}", 
        params: { 
          issue: { 
            notes: wiki_content 
          } 
        }
    
    follow_redirect! if response.redirect?
    
    # Should render thumbnail macro properly
    assert_response :success
    assert_select 'a.thumbnail', count: 1
  end

  def test_attachment_visibility_with_cloud_files
    # Test that cloud attachments respect visibility rules
    log_user('jsmith', 'jsmith')
    
    # Should be able to access if user has permission
    get "/attachments/#{@cloud_attachment.id}"
    assert_response :success
    
    # Test with anonymous user
    reset_session
    get "/attachments/#{@cloud_attachment.id}"
    assert_response :redirect # Should redirect to login
  end

  def test_error_handling_for_invalid_cloud_attachments
    log_user('jsmith', 'jsmith')
    
    # Test with non-existent attachment
    get "/attachments/download/99999/nonexistent.jpg"
    assert_response :not_found
    
    # Test thumbnail for non-existent attachment
    get "/attachments/thumbnail/99999"
    assert_response :not_found
  end

  def test_performance_optimization
    log_user('jsmith', 'jsmith')
    
    # Multiple requests should be handled efficiently
    start_time = Time.current
    
    5.times do
      get "/attachments/#{@cloud_attachment.id}"
      assert_response :success
    end
    
    duration = Time.current - start_time
    
    # Should complete reasonably quickly (adjust threshold as needed)
    assert duration < 5.seconds, "Multiple requests should be handled efficiently"
  end

  private

  def assert_response_in(expected_statuses, message = nil)
    assert_includes expected_statuses, response.status, message || "Expected response to be one of #{expected_statuses}, got #{response.status}"
  end

  def convert_installed?
    Redmine::Thumbnail.convert_available?
  end

  def log_user(login, password)
    post '/login', params: { username: login, password: password }
    assert_response :redirect
    assert_redirected_to '/my/page'
    follow_redirect!
  end
end 
