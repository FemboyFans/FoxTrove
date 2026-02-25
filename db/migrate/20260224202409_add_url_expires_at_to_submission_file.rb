class AddUrlExpiresAtToSubmissionFile < ActiveRecord::Migration[8.1]
  def change
    add_column(:submission_files, :direct_url_expires_at, :datetime)
    add_column(:submission_files, :direct_url_data, :jsonb)
  end
end
