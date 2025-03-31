class E6UpdateReplacedJob < ApplicationJob
  def perform(artist_url)
    raise StandardError, "Provided artist url is not site_type==e621" unless artist_url.site_type == "e621"
    posts = E6ApiClient.get_all_posts(artist_url.url_identifier)
    posts.each do |post|
      submission = artist_url.submissions.find_by(identifier_on_site: post["id"])
      files = submission&.submission_files
      next if submission.blank? || files.blank? || files.any? { |f| f.md5 == post["file"]["md5"] }
      sub = to_submission(submission)
      sub.add_file({
        url: post["file"]["url"],
        created_at: submission.created_at,
        identifier: post["file"]["md5"],
      })
      sub.save(artist_url)
    end
  end
end
