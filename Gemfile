source "https://rubygems.org"

gem "rails", "~> 8.1"
gem "puma", "~> 8.0"

group :development, :test do
  gem "brakeman", require: false
end

# Read-only billing data (PRD 7.1). Credentials come only from the ECS task role.
gem "aws-sdk-cloudwatch", "~> 1.0"
gem "aws-sdk-costexplorer", "~> 1.0"
