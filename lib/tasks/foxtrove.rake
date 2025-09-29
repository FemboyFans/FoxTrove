namespace :foxtrove do
  desc "Generate the icon spritemap"
  task generate_spritemap: :environment do
    IconGenerator.run
  end

  desc "Backfill missing api identifiers after adding a new scraper"
  task backfill_api_identifiers: :environment do
    site_type = ENV.fetch("SITE_TYPE", nil)
    raise StandardError, "Must provide a site type" if site_type.blank?

    ArtistUrl.where(api_identifier: nil, site_type: site_type).find_each do |artist_url|
      puts artist_url.url_identifier
      artist_url.update(api_identifier: artist_url.scraper.fetch_api_identifier)
    end
  end

  task update_e6_replaced_posts: :environment do
    ArtistUrl.where(site_type: "e621").find_each(&:update_e6_replaced)
  end
end
