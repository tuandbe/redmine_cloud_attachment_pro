#!/bin/bash

# Script to setup test database for Redmine plugin testing
# Based on official Redmine Plugin Tutorial documentation

echo "🚀 Setting up test database for redmine_cloud_attachment_pro plugin..."

# Navigate to Redmine root
cd "$(dirname "$0")/../../.."

# Set test environment
export RAILS_ENV=test

echo "📋 Step 1: Drop and recreate test database..."
bundle exec rake db:drop db:create

echo "📋 Step 2: Run core Redmine migrations..."
bundle exec rake db:migrate

echo "📋 Step 3: Run plugin migrations..."
bundle exec rake redmine:plugins:migrate

echo "📋 Step 4: Load default data..."
bundle exec rake redmine:load_default_data

echo "✅ Test database setup completed!"
echo "💡 Now you can run tests with:"
echo "   RAILS_ENV=test bundle exec rake test TEST=plugins/redmine_cloud_attachment_pro/test/unit/cloud_attachment_optimization_test.rb"
echo "   Or run all plugin tests:"
echo "   RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=redmine_cloud_attachment_pro" 
