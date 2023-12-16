# frozen_string_literal: true

class AddArtistUrlsPostCount < ActiveRecord::Migration[7.1]
  def change
    add_column :artist_urls, :post_count, :integer, null: true
  end
end
