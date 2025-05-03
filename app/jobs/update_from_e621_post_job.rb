class UpdateFromE621PostJob < ApplicationJob
  queue_as :e621_sync

  VALID_EXTENSIONS = %w[png jpg].freeze
  def perform(_artist_url, post)
    sub = SubmissionFile.find_by_md5(post.dig("file", "md5")) # rubocop:disable Rails/DynamicFindBy
    create_e6_post(sub, post) if sub.present?
    return unless VALID_EXTENSIONS.include?(post.dig("file", "ext"))

    sample = post["variants"].find { |s| s["type"] == "large" }
    sample_url = sample&.[]("url") || post.dig("file", "url")
    results = IqdbProxy.query_url(sample_url)

    results.each do |res|
      next unless res[:score] > 60

      sub = res[:submission_file]
      sub.e6_posts.destroy_all

      post_entry = create_e6_post(sub, post)

      # Check if there are entries which were previously added
      # that are an exact visual match to this newly added exact match
      if post_entry.is_exact_match
        sub.existing_matches(post["id"], is_exact_match: false).find_each do |existing_match|
          existing_match.update(is_exact_match: true)
        end
      end
    end
  end

  def create_e6_post(submission, post)
    submission.e6_posts.create(
      post_id: post["id"],
      post_width: post["file"]["width"],
      post_height: post["file"]["height"],
      post_size: post["file"]["size"],
      post_is_deleted: post["flags"]["deleted"],
      post_json: post,
      similarity_score: post["score"]["total"],
      is_exact_match: submission.md5 == post["file"]["md5"] || submission.existing_matches(post["id"], is_exact_match: true).any?,
    )
  end
end
