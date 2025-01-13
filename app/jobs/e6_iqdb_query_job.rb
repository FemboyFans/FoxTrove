class E6IqdbQueryJob < ConcurrencyControlledJob
  queue_as :e6_iqdb
  good_job_control_concurrency_with(
    total_limit: -> { "unique-job-#{arguments.first.id}" },
    perform_limit: 2
  )

  PRIORITIES = {
    immediate: 0,
    manual_action: 90,
    automatic_action: 100,
  }.freeze

  def perform(submission_file)
    submission_file.update_e6_posts!
  end
end
