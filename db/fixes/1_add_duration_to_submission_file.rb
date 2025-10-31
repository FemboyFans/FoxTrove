#!/usr/bin/env ruby
# frozen_string_literal: true

require(File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "config", "environment")))

SubmissionFile.where(duration: nil)
          .joins(original_attachment: :blob)
          .where("active_storage_blobs.content_type LIKE ?", "video/%")
          .find_each do |submission|
  blob = submission.original.blob
  analyzer = ActiveStorage::Analyzer::VideoAnalyzer.new(blob)

  begin
    metadata = analyzer.metadata
    duration = metadata[:duration]

    if duration.present?
      submission.update!(duration: duration)
      puts submission.id
    end

  rescue => e
    puts "Failed ##{submission.id}: #{e.class}: #{e.message}"
  end
end
