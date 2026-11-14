# Starts the background cost refresh once the app has booted (PRD R5).
# See CostRefresher.enabled? for when it runs.
Rails.application.config.after_initialize do
  CostRefresher.start if CostRefresher.enabled?
end
