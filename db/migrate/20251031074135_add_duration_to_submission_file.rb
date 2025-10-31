class AddDurationToSubmissionFile < ActiveRecord::Migration[8.0]
  def change
    add_column(:submission_files, :duration, :integer)
  end
end
