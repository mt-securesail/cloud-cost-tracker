require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  # HTTPS only (PRD S1, S2). The ALB terminates TLS and forwards plain HTTP to
  # the container, so assume_ssl tells Rails every request arrived over HTTPS.
  # force_ssl then sends HSTS and secure cookies. Its redirect never fires
  # behind the ALB (the ALB already redirects port 80 to 443); /up is excluded
  # so health checks always get a plain 200.
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Only answer requests addressed to this app's hostname (PRD S3), which
  # blocks Host-header attacks. ALLOWED_HOSTS (comma-separated) overrides the
  # default; the ZAP scan on pull requests sets it to its container name.
  # /up is excluded because ALB health checks use the task's IP address.
  config.hosts = ENV.fetch("ALLOWED_HOSTS", "aws-cost-est.example-apps.com").split(",").map(&:strip)
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  config.log_tags = [:request_id]
  logger           = ActiveSupport::Logger.new(STDOUT)
  logger.formatter = ::Logger::Formatter.new
  config.logger    = ActiveSupport::TaggedLogging.new(logger)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  config.action_controller.perform_caching = true

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
end
