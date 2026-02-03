class SubmissionFilesController < ApplicationController
  def index
    @search_params = search_params
    @artist_submission = ArtistSubmission.find_by(id: @search_params[:artist_submission_id]) if @search_params[:artist_submission_id]
    @paginator, @submission_files = SubmissionFile.search(@search_params).with_everything.paginate(params)
  end

  def show
    @submission_file = SubmissionFile.find(params[:id])
    @artist_submission = @submission_file.artist_submission
    @similar = @submission_file.iqdb_similar
  end

  def destroy
    @submission_file = SubmissionFile.find(params[:id])
    @submission_file.destroy
    redirect_back_or_to(submission_files_path(search: { artist_submission_id: @submission_file.artist_submission_id } ))
  end

  def upload
    @submission_file = SubmissionFile.find(params[:id])
    url = @submission_file.upload_url
    if url.nil?
      flash[:notice] = "No upload url"
      return redirect_back_or_to(submission_file_path(@submission_file))
    end
    redirect_to(url, allow_other_host: true)
  end

  def modify_backlog
    submission_file = SubmissionFile.find(params[:id])
    in_backlog = params[:type] == "add"
    submission_file.update(added_to_backlog_at: in_backlog ? Time.current : nil)
  end

  def modify_hidden
    submission_file = SubmissionFile.find(params[:id])
    hide_from_search = params[:type] == "add"
    submission_file.update(hidden_from_search_at: hide_from_search ? Time.current : nil)
  end

  def set_last_known_good
    submission_file = SubmissionFile.find(params[:id])
    submission_file.artist_url.update(last_scraped_at: submission_file.created_at_on_site - 1.day)
  end

  def update_e6_posts
    submission_file = SubmissionFile.find(params[:id])
    submission_file.update_e6_posts(priority: E6IqdbQueryJob::PRIORITIES[:immediate])
  end

  def update_matching_e6_posts
    UpdateMatchingE6PostsJob.perform_later(search_params)
  end

  def backlog
    @search_params = search_params.merge(in_backlog: true)
    @paginator, @submission_files = SubmissionFile.search(@search_params)
      .with_everything
      .reorder(added_to_backlog_at: :desc)
      .paginate(params)
  end

  def hidden
    @search_params = search_params.merge(hidden_from_search: true)
    @paginator, @submission_files = SubmissionFile.search(@search_params)
      .with_everything
      .reorder(hidden_from_search_at: :desc)
      .paginate(params)
  end

  def hide_many
    SubmissionFile.where(id: params[:ids], hidden_from_search_at: nil).find_each do |submission_file|
      submission_file.update(hidden_from_search_at: Time.current)
    end
  end

  def unhide_many
    SubmissionFile.where(id: params[:ids]).where.not(hidden_from_search_at: nil).find_each do |submission_file|
      submission_file.update(hidden_from_search_at: nil)
    end
  end

  def backlog_many
    SubmissionFile.where(id: params[:ids], added_to_backlog_at: nil).find_each do |submission_file|
      submission_file.update(added_to_backlog_at: Time.current)
    end
  end

  def unbacklog_many
    SubmissionFile.where(id: params[:ids]).where.not(added_to_backlog_at: nil).find_each do |submission_file|
      submission_file.update(added_to_backlog_at: nil)
    end
  end

  def enqueue_many
    SubmissionFile.where(id: params[:ids]).find_each(&:update_e6_posts)
  end

  private

  def search_params
    params.fetch(:search, {}).permit(SubmissionFile.search_params)
  end
end
