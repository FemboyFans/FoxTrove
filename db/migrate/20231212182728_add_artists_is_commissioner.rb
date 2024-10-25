class AddArtistsIsCommissioner < ActiveRecord::Migration[7.1]
  def change
    add_column :artists, :is_commissioner, :boolean, null: false, default: false
  end
end
