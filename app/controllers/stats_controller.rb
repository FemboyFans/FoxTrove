class StatsController < ApplicationController
  def index
    @original_size = sum_for("original", "SubmissionFile")
    @sample_size = sum_for("sample", "SubmissionFile")
    db_name = Rails.configuration.database_configuration[Rails.env]["database"]
    @db_size = ActiveRecord::Base.connection.execute("SELECT pg_database_size('#{db_name}');").first["pg_database_size"]
    @counts = SubmissionFile.select(
      :site_type,
      "count(distinct artist_id) as artist_count",
      "count(distinct artist_url_id) as url_count",
      "count(distinct artist_submission_id) as submission_count",
      "count(*) as file_count",
    ).joins(artist_submission: { artist_url: :artist }).group(:site_type).index_by(&:site_type)
    @counts.transform_keys! { |id| ArtistUrl.site_types.invert[id] }
    @definitions = Sites.definitions.sort_by(&:display_name)
    respond_to do |fmt|
      fmt.html
      fmt.json do
        render json: {
          artist_urls: render_to_string(partial: "artist_urls/list", formats: %i[html], locals: { artist_urls: ArtistUrl.where(id: helpers.job_stats.active_urls) }),
          scraped: @counts,
          storage: {
            db: helpers.number_to_human_size(@db_size),
            original: helpers.number_to_human_size(@original_size),
            samples: helpers.number_to_human_size(@sample_size),
          },
          jobs: {
            scraping: helpers.job_stats.scraping_queued.values.sum,
            file_downloads: helpers.job_stats.submission_download_queued.values.sum,
            iqdb: helpers.job_stats.e6_iqdb_queued.values.sum,
            post_sync: helpers.job_stats.e621_sync_queued.values.sum,
          },
        }
      end
    end
  end

  def selenium
    render json: { active: SeleniumWrapper.active? }
  end

  private

  def sum_for(name, record_type)
    ActiveStorage::Blob.joins(:attachments).where(attachments: { name: name, record_type: record_type }).sum(:byte_size)
  end
end
