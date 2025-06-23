# Redmine Cloud Attachment Pro

A plugin for Redmine that enables storing attachments in multiple cloud backends (S3, Google Cloud Storage, Azure Blob Storage) with direct download optimization.

## Key Features

- **Multiple Cloud Backends**: Support for AWS S3, Google Cloud Storage, and Azure Blob Storage
- **Direct Download Optimization**: Offloads file serving to cloud storage using presigned URLs
- **Bandwidth Saving**: Reduces server bandwidth usage by redirecting users directly to cloud storage
- **Performance Boost**: Eliminates temporary file creation for cloud attachments
- **API Integration**: Enhanced API responses with direct cloud URLs
- **Fallback Support**: Graceful fallback to local serving when cloud access fails

## Performance Benefits

### Before Optimization:
```
User Request → Redmine → Download from Cloud → Create Temp File → Serve to User
```

### After Optimization:
```
User Request → Redmine → Generate Presigned URL → Redirect User to Cloud Storage
```

**Results:**
- ⚡ **Faster downloads** - Direct access to cloud storage
- 💾 **No temporary files** - Eliminates disk space consumption  
- 🚀 **Reduced server load** - Offloads file serving to cloud providers
- 📊 **Lower bandwidth costs** - Files served directly from cloud storage

## Configuration

### Basic Storage Configuration

Add to your `config/configuration.yml`:

```yaml
production:
  # Set storage backend
  storage: s3  # or 'gcs' or 'azure'
  
  # S3 Configuration
  s3:
    access_key_id: "your_access_key"
    secret_access_key: "your_secret_key"
    bucket: "your_bucket_name"
    region: "your_region"
    path: "redmine/files"  # Optional: custom path prefix
  
  # Google Cloud Storage Configuration  
  gcs:
    project_id: "your_project_id"
    bucket: "your_bucket_name"
    gcs_credentials: "/path/to/service_account.json"
    path: "redmine/files"
  
  # Azure Blob Storage Configuration
  azure:
    account_name: "your_account_name" 
    access_key: "your_access_key"
    container: "your_container_name"
    path: "redmine/files"
```

### Advanced Configuration

```yaml
production:
  # Cloud Attachment Pro specific settings
  cloud_attachment_pro:
    # Presigned URL expiration time (in minutes, default: 15)
    presigned_url_expires_in: 60
```

## Installation

1. Copy this plugin to your Redmine plugins directory:
   ```bash
   cd /path/to/redmine
   git clone https://github.com/your-repo/redmine_cloud_attachment_pro.git plugins/redmine_cloud_attachment_pro
   ```

2. Install dependencies:
   ```bash
   cd plugins/redmine_cloud_attachment_pro
   bundle install
   ```

3. Configure your cloud storage settings in `config/configuration.yml`

4. Restart Redmine:
   ```bash
   sudo systemctl restart redmine
   # or if using Passenger/Puma
   touch tmp/restart.txt
   ```

## Monitoring and Logs

Monitor the plugin performance through log entries:

```bash
# Monitor direct cloud redirects
tail -f log/production.log | grep "CloudAttachmentPro.*Redirecting to presigned URL"

# Monitor fallbacks to local serving  
tail -f log/production.log | grep "CloudAttachmentPro.*Using original download method"

# Monitor potential issues
tail -f log/production.log | grep "CloudAttachmentPro.*ERROR"
```

## API Enhancements

The plugin enhances API responses with direct cloud URLs:

```json
{
  "attachment": {
    "id": 123,
    "filename": "document.pdf",
    "content_url": "/attachments/download/123/document.pdf",
    "direct_content_url": "https://bucket.s3.amazonaws.com/path/to/file?X-Amz-..."
  }
}
```

Use `direct_content_url` for optimal performance in API clients.

## Troubleshooting

### Common Issues

1. **Files not redirecting to cloud storage**
   - Check cloud configuration in `configuration.yml`
   - Verify storage backend is set correctly
   - Check logs for error messages

2. **Presigned URL generation failures**
   - Verify cloud credentials are correct
   - Check cloud provider IAM permissions
   - Ensure bucket/container exists

3. **Images not displaying directly**
   - Verify CORS settings on your cloud storage
   - Check browser network tab for failed requests

### Debugging

Enable debug logging by adding to your configuration:

```yaml
production:
  log_level: debug
```

## Migration from Local Storage

To migrate existing local attachments to cloud storage:

1. Configure cloud storage settings
2. Set `storage: your_cloud_backend` in configuration
3. New uploads will go to cloud storage
4. Existing local files remain accessible
5. Optionally migrate old files using custom scripts

## Security Notes

- Presigned URLs have configurable expiration times
- All Redmine permission checks are preserved
- Cloud access requires valid Redmine session
- Direct URLs are temporary and expire automatically

## Supported Cloud Providers

- **AWS S3**: Full support with presigned URLs
- **Google Cloud Storage**: Full support with signed URLs  
- **Azure Blob Storage**: Full support with SAS tokens

## Performance Monitoring

Key metrics to monitor:

- Percentage of requests using direct cloud URLs vs local serving
- Reduction in server bandwidth usage
- Improvement in download speeds
- Reduction in temporary file creation

## License

This plugin is released under the same license as Redmine.

## Support

For issues and feature requests, please use the GitHub issue tracker.
