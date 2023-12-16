# frozen_string_literal: true

class SyncFromE621Job < ApplicationJob
  def perform(artist)
    raise StandardError, "Artist does not have e621 tag" if artist.e621_tag.blank?

    posts = E6ApiClient.get_all_posts(artist.e621_tag)
    url = artist.e621_url
    url.update!(post_count: posts.length, last_scraped_at: Time.current)
    posts.each do |post|
      UpdateFromE621PostJob.perform_later(url, post)
    end
  end
end
