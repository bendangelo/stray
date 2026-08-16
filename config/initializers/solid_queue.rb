# Solid Queue tuning for single-process, SQLite-backed self-hosting.
#
# Stray runs the Solid Queue supervisor inside the Puma process (see the
# `plugin :solid_queue` in config/puma.rb) so that a single process serves web
# requests and runs background jobs. These settings reduce per-job SQLite
# contention and keep a job thread failure from taking down the web process.

Rails.application.config.to_prepare do
  # Log thread errors through Rails instead of crashing the hosting process.
  SolidQueue.on_thread_error = ->(error) { Rails.logger.error("#{error.class}: #{error.message}") }

  # Finished job rows are cleared hourly by the recurring clear task
  # (config/recurring.yml), so keep them for a short window for inspection.
  SolidQueue.preserve_finished_jobs = true
  SolidQueue.clear_finished_jobs_after = 1.day
end
