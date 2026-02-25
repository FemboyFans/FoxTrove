class CreateSubmissionFileJob < ConcurrencyControlledJob
  queue_as :submission_download
  good_job_control_concurrency_with(total_limit: 1, key: -> { "#{arguments.first.id}-#{arguments.second[:identifier]}" })

  def perform(artist_submission, file)
    submission_file = SubmissionFile.find_by(artist_submission: artist_submission, file_identifier: file[:identifier])
    return if submission_file

    create = -> (url, bin_file, **kwargs) do
      SubmissionFile.from_attachable(
        attachable: bin_file,
        artist_submission: artist_submission,
        url: url,
        url_expires_at: file[:url_expires_at],
        url_data: file[:url_data],
        created_at: file[:created_at],
        file_identifier: file[:identifier],
        **kwargs
      )
    end

    if file[:file]
      bin_file = File.open(file[:file])
      create.call(file[:url] || "file://#{bin_file.path}", bin_file, filename: File.basename(bin_file.path))
      File.delete(file[:file]) if file[:rm_file] && File.exist?(file[:file])
    else
      # Some download links expire, they need to be fetched when we actually use them
      url = file[:url].presence
      if file[:url_expires_at] && file[:url_expires_at] < Time.now
        if file[:url_data].present?
          url = artist_submission.artist_url.scraper.get_download_url(file[:url_data])
        else
          raise("No url to download (expired & no data)")
        end
      end
      raise("No url to download") if url.nil?
      Sites.download_file(url, artist_submission: artist_submission) do |bin_file|
        create.call(url, bin_file)
      rescue SubmissionFile::ContentTypeError, SubmissionFile::AnalysisError => e
        Rails.logger.error("Error downloading file: #{e.class.name} #{e.message}")
      end
    end
  end
end
