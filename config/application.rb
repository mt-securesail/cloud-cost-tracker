require_relative "boot"

require "rails"
require "action_controller/railtie"

Bundler.require(*Rails.groups)

module CloudCostTracker
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    # No database, no asset pipeline. This app is intentionally minimal.
    config.api_only = false
  end
end
