class HomeController < ApplicationController
  # How often the page asks /summary.json for new data (PRD R1). The data
  # changes only a few times a day; this just picks it up reasonably soon.
  POLL_SECONDS = 300

  SCRIPT_PATH = Rails.root.join("app/javascript/dashboard.js")

  # Rails blocks .js responses to non-XHR GETs, to stop other sites reading
  # private data through <script src> (JSONP-style leaks). dashboard.js is a
  # fixed file with no data in it, loaded by this app's own <script src>, so
  # that check is skipped for it only. CSRF token checks are unaffected.
  skip_after_action :verify_same_origin_request, only: :script

  # Reads only the in-memory CostStore: a page view never calls AWS (PRD R1).
  def index
    @app_version = app_version
    @payload = helpers.summary_payload(CostSummary.new, version: @app_version)
  end

  # Same data as the page, for in-place updates. Also never calls AWS.
  def summary
    # to_json escapes <, >, and & as < etc. (Rails 8.1's `render json:`
    # no longer does). Defense in depth: names from AWS can't look like HTML
    # even if something treats the response as HTML.
    render json: helpers.summary_payload(CostSummary.new, version: app_version).to_json
  end

  def script
    render plain: SCRIPT_PATH.read, content_type: "text/javascript"
  end

  private

  def app_version
    ENV.fetch("APP_VERSION", "dev")
  end
end
