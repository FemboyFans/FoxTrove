class ArtistUrlsController < ApplicationController
  def index
    @paginator, @artist_urls = ArtistUrl.search(index_search_params).paginate(params)
  end

  def show
    @artist_url = ArtistUrl.find(params[:id])
    redirect_to artist_path(@artist_url.artist, search: { artist_url_id: [params[:id]] })
  end

  def destroy
    artist_url = ArtistUrl.includes(submissions: :submission_files).find(params[:id])
    artist_url.destroy
    flash[:notice] = "URL deleted"
    redirect_back_or_to(artist_path(artist_url.artist))
  end

  def enqueue
    artist_url = ArtistUrl.find(params[:id])
    artist_url.enqueue_scraping
    flash[:notice] = "scraping enqueued"
    redirect_back_or_to(artist_path(artist_url.artist))
  end

  def disable
    artist_url = ArtistUrl.find(params[:id])
    artist_url.disable!
    flash[:notice] = "URL disabled"
    redirect_back_or_to(artist_path(artist_url.artist))
  end

  def enable
    artist_url = ArtistUrl.find(params[:id])
    artist_url.enable!
    flash[:notice] = "URL enabled"
    redirect_back_or_to(artist_path(artist_url.artist))
  end

  def hide
    artist_url = ArtistUrl.find(params[:id])
    artist_url.hide!
    flash[:notice] = "URL hidden"
    redirect_back_or_to(artist_path(artist_url.artist))
  end

  def unhide
    artist_url = ArtistUrl.find(params[:id])
    artist_url.unhide!
    flash[:notice] = "URL unhidden"
    redirect_back_or_to(artist_path(artist_url.artist))
  end

  private

  def index_search_params
    params.fetch(:search, {}).permit(:site_type, :url_identifier, :api_identifier, :missing_api_identifier, :is_disabled, :is_hidden)
  end
end
