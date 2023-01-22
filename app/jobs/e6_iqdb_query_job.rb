# frozen_string_literal: true

class E6IqdbQueryJob < ApplicationJob
  queue_as :e6_iqdb
  good_job_control_concurrency_with(total_limit: 1, key: -> { arguments.first })

  PRIORITIES = {
    immediate: 100,
    manual_action: 10,
    automatic_action: 0,
  }.freeze

  def perform(submission_file_id)
    submission_file = SubmissionFile.find_by id: submission_file_id
    return unless submission_file

    submission_file.update_e6_posts!
  end
end
