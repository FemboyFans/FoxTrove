class ArtistsController < ApplicationController
  def index
    @paginator, @artists = Artist.includes(:artist_urls).search(index_search_params).paginate(params)

    @artist_urls_count = ArtistUrl.select(:artist_id)
      .where(artist: @artists).group(:artist_id).count
    @submissions_count = ArtistSubmission.select(:artist_id).joins(:artist_url)
      .where(artist_url: { artist: @artists }).group(:artist_id).count

    base = SubmissionFile.select(:artist_id).joins(artist_submission: :artist_url)
      .where("artist_url.artist_id": @artists.map(&:id)).group("artist_url.artist_id")
    @submission_files_count = base.count
    @not_uploaded_count = base.search(upload_status: "not_uploaded").reorder("").count
    @larger_size_count = base.search(upload_status: "larger_only_filesize_percentage").reorder("").count
    @larger_dimensions_count = base.search(upload_status: "larger_only_dimensions").reorder("").count
  end

  def show
    @artist = Artist.includes(:artist_urls).find(params[:id])
    @search_params = instance_search_params.merge(artist_id: @artist.id)
    @paginator, @submission_files = SubmissionFile.search(@search_params).with_everything.paginate(params)
    @e6 = @submission_files.select { |sf| sf.artist_url.site_type == "e621" }
    E6ApiClient.get_posts_cached(@e6.map { |sf| sf.artist_submission.identifier_on_site.to_i })
  end

  def new
    @artist = Artist.new
  end

  def edit
    @artist = Artist.includes(:artist_urls).find(params[:id])
  end

  def create
    Artist.transaction do
      @artist = Artist.create(artist_params)
      add_new_artist_urls(@artist) if @artist.valid?

      if @artist.errors.any?
        raise ActiveRecord::Rollback
      end
    end
    respond_with(@artist)
  end

  def update
    @artist = Artist.find(params[:id])
    @artist.update(artist_params)
    add_new_artist_urls(@artist)
    respond_with(@artist)
  end

  def destroy
    @artist = Artist.includes(artist_urls: { submissions: :submission_files }).find(params[:id])
    @artist.destroy
    redirect_to artists_path
  end

  def enqueue_all_urls
    @artist = Artist.find(params[:id])
    @artist.enqueue_all_urls
  end

  def enqueue_everything
    Artist.find_each(&:enqueue_all_urls)
  end

  def sync_e621
    Artist.find(params[:id]).sync_e621
  end

  private

  def artist_params
    permitted_params = %i[name url_string is_commissioner]

    params.fetch(:artist, {}).permit(permitted_params)
  end

  def index_search_params
    params.fetch(:search, {}).permit(:name, :url_identifier, :site_type, :is_commissioner, :e621_tag)
  end

  def instance_search_params
    params.fetch(:search, {}).permit(SubmissionFile.search_params)
  end

  def add_new_artist_urls(artist)
    artist.url_string.lines.map(&:strip).compact_blank.each do |url|
      artist.add_artist_url(url)
    end
  end
end
