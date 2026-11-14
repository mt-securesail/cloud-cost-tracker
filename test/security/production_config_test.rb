require "test_helper"
require "json"
require "open3"

# Regression tests for the production-only settings in
# config/environments/production.rb (PRD S1-S3): HTTPS-only with HSTS, and
# requests answered only for this app's hostname. Those settings don't load in
# the test environment, so this boots the app in production mode in a separate
# process and sends it requests directly (no network, no AWS).
class ProductionConfigTest < ActiveSupport::TestCase
  HOST = "aws-cost-est.example-apps.com"

  PROBE = <<~RUBY
    require "json"
    app = Rack::MockRequest.new(Rails.application)
    result = {
      home:      app.get("http://#{HOST}/", "HTTP_HOST" => "#{HOST}"),
      evil_host: app.get("http://evil.example/", "HTTP_HOST" => "evil.example"),
      health:    app.get("http://10.0.0.5:3000/up", "HTTP_HOST" => "10.0.0.5:3000")
    }.transform_values { |r| { status: r.status, hsts: r.headers["strict-transport-security"], location: r.headers["location"] } }
    puts "PROBE_RESULT " + JSON.dump(result)
  RUBY

  def self.probe
    @probe ||= begin
      env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE" => "0" * 64, "ALLOWED_HOSTS" => nil }
      out, status = Open3.capture2e(env, "bin/rails", "runner", PROBE, chdir: Rails.root.to_s)
      line = out.lines.find { |l| l.start_with?("PROBE_RESULT ") }
      raise "production probe failed (exit #{status.exitstatus}):\n#{out}" unless line
      JSON.parse(line.delete_prefix("PROBE_RESULT "))
    end
  end

  test "pages are served over (assumed) HTTPS with HSTS, without redirect loops" do
    home = self.class.probe["home"]
    assert_equal 200, home["status"], "behind the ALB, a request for the app's host must get the page, not a redirect"
    assert_match(/max-age=\d+/, home["hsts"].to_s, "Strict-Transport-Security header is missing")
  end

  test "requests for any other hostname are refused" do
    assert_equal 403, self.class.probe["evil_host"]["status"]
  end

  test "ALB health checks on /up work by IP address" do
    assert_equal 200, self.class.probe["health"]["status"]
  end
end
