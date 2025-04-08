# Redmine Cloud Attachment Pro

**Redmine Cloud Attachment Pro** is a versatile Redmine plugin that enables dynamic storage of file attachments in multiple backends like Local Disk, Amazon S3, and future support for Google Cloud Storage and Microsoft Azure Blob Storage.

## 🔧 Features

- Seamless integration with Redmine's attachment system.
- Store files in:
  - 🖥️ Local filesystem (default)
  - ☁️ Amazon S3 (currently supported)
  - 🌐 Future support for Google Cloud Storage and Azure Blob Storage
- Automatically uploads new attachments to the selected storage backend.
- Secure and efficient download handling from cloud sources.
- Clean deletion of attachments from cloud when removed from Redmine.
- Backward compatible and configurable per environment.

## ⚙️ Configuration

### Step 1: Add storage config to `config/configuration.yml`

```yaml
# config/configuration.yml
default:
  storage: s3 # or 'local'
  s3:
    access_key_id: YOUR_ACCESS_KEY
    secret_access_key: YOUR_SECRET_KEY
    region: YOUR_REGION
    bucket: YOUR_BUCKET_NAME
    path: redmine/files
```

Set storage to either:

local for filesystem storage (default Redmine behavior)
s3 for AWS S3
Future options like gcs or azure can be added similarly.

Step 2: Install and Migrate

```bash
bundle install
```

No migrations are needed for this plugin.

Step 3: Optional Rake Task
To update existing attachment filenames to include the S3 prefix:

```bash
bundle exec rake attachments:prefix_s3_filenames RAILS_ENV=production
```

How it Works
Automatically detects and uploads new files to the selected storage.
Downloads from cloud storage when users request the file.
Deletes files from the cloud when an attachment is destroyed.

🔐 Security
All cloud credentials are securely pulled from configuration.yml. Avoid committing secrets to version control.


Compatibility
Redmine 5.x and above
Ruby 3.x and Rails 6.x or later
AWS SDK v3

🚀 Roadmap

✅ Amazon S3 Support

⏳ Google Cloud Storage Support

⏳ Microsoft Azure Blob Support

⏳ Web UI for configuring storage

📁 Plugin Installation

Clone into Redmine's plugin directory:

```bash
git clone https://github.com/railsfactory-sivamanikandan/redmine_cloud_attachment_pro plugins/redmine_cloud_attachment_pro
```

Then restart Redmine.


Author
Maintained by Sivamanikandan, Sedin Technologies Pvt Ltd, Chennai

📄 License
MIT License