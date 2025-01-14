class ArtistSubmission < ApplicationRecord
  belongs_to :artist_url
  has_one :artist, through: :artist_url
  has_many :submission_files, dependent: :destroy

  validates :identifier_on_site, uniqueness: { scope: :artist_url_id, case_sensitive: false }

  delegate :site, to: :artist_url

  def self.for_site_with_identifier(site:, identifier:)
    joins(:artist_url).find_by(identifier_on_site: identifier, artist_url: { site_type: site })
  end

  def update_fa!
    html = artist_url.scraper.send(:get_submission_html, identifier_on_site)
    title = html.css(".submission-title").first&.content&.strip
    description = html.css(".submission-description").first&.content&.strip
    self.title_on_site = title if title.present?
    self.description_on_site = description if description.present?
    save!
  end
end
