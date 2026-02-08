class AddIsDisabledAndIsHiddenToArtistUrls < ActiveRecord::Migration[8.1]
  def change
    add_column(:artist_urls, :is_disabled, :boolean, null: false, default: false)
    add_column(:artist_urls, :is_hidden, :boolean, null: false, default: false)
  end
end
