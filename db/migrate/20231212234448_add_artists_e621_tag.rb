class AddArtistsE621Tag < ActiveRecord::Migration[7.1]
  def change
    add_column :artists, :e621_tag, :string, null: true
  end
end
