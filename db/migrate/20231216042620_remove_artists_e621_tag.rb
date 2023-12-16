# frozen_string_literal: true

class RemoveArtistsE621Tag < ActiveRecord::Migration[7.1]
  def change
    remove_column :artists, :e621_tag, :string
  end
end
