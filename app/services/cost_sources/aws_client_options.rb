module CostSources
  # Shared AWS SDK client settings. Short timeouts so a slow AWS response can't
  # tie up the refresher, and few retries, because every Cost Explorer request
  # (including a retry) costs $0.01 (PRD N3).
  module AwsClientOptions
    DEFAULTS = {
      http_open_timeout: 5,
      http_read_timeout: 20,
      retry_mode: "standard",
      max_attempts: 2
    }.freeze
  end
end
