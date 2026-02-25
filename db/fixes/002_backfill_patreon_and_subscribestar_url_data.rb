#!/usr/bin/env ruby
# frozen_string_literal: true
require(File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "config", "environment")))
ActiveRecord::Base.logger = nil

ArtistUrl.where(site_type: "patreon").includes(submissions: :submission_files).find_each do |artist_url|
  scraper = artist_url.scraper
  scraper.jumpstart(Time.at(0).iso8601)
  submissions = scraper.fetch_next_batch
  submissions.each do |sub|
    post = sub.find { |s| s.length == 2 }.try(:[], 1)
    next if post.nil?
    artsub = artist_url.submissions.find { |s| s.identifier_on_site == post["id"].to_s }
    images = sub.select { |s| s.length == 3 }
    next if artsub.nil? || images.none?
    images.each do |(_index, url, img)|
      id = img.dig("file", "file_name") || "#{img['hash']}-#{File.basename(URI.parse(url).path)}"
      file = artsub.submission_files.find { |s| s.file_identifier == id }
      next unless file
      puts "site=#{artist_url.site_type} post=#{img['id']} sub=#{artsub.id} img=#{id}"
      file.update(direct_url: url, direct_url_data: [img["id"], img.dig("file", "display", "media_id")], direct_url_expires_at: scraper.send(:parse_url_expiry, url))
    end
  end
end

ArtistUrl.where(site_type: %w[subscribestar subscribestar_adult]).includes(submissions: :submission_files).find_each do |artist_url|
  scraper = artist_url.scraper
  scraper.jumpstart(Time.at(0).iso8601)
  submissions = scraper.fetch_next_batch
  submissions.each do |sub|
    post = sub.find { |s| s.length == 2 }.try(:[], 1)
    next if post.nil?
    artsub = artist_url.submissions.find { |s| s.identifier_on_site == post["post_id"].to_s }
    images = sub.select { |s| s.length == 3 }
    next if artsub.nil? || images.none?
    images.each do |(_index, url, img)|
      url = scraper.send(:resolve_url, url)
      id = img["id"].to_s
      file = artsub.submission_files.find { |s| s.file_identifier == id }
      next unless file
      puts "site=#{artist_url.site_type} post=#{img['id']} sub=#{artsub.id} img=#{id}"
      file.update(direct_url: url, direct_url_data: [img["post_id"], img["id"]], direct_url_expires_at: scraper.send(:parse_url_expiry, url))
    end
  end
end
