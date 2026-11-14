class HomeController < ApplicationController
  # Reads only the in-memory CostStore: a page view never calls AWS (PRD R1).
  def index
    @app_version = ENV.fetch("APP_VERSION", "dev")
    @summary = CostSummary.new
  end
end
