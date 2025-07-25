class SubmissionFile < ApplicationRecord
  class AnalysisError < StandardError; end
  class ContentTypeError < StandardError; end

  belongs_to :artist_submission
  has_one :artist, through: :artist_submission
  has_many :e6_posts, dependent: :destroy
  has_many :relevant_e6_posts, -> { where(similarity_score: Config.similarity_cutoff..) }, inverse_of: :submission_file, dependent: nil, class_name: "E6Post"

  validate :original_present

  after_destroy_commit :remove_from_iqdb
  after_save_commit :update_variants_and_iqdb
  # This adds framework after_commit hooks which must run after
  # the ones above for attachment_changes to work correctly
  has_one_attached :original
  has_one_attached :sample

  scope :with_attached, -> { with_attached_sample.with_attached_original }
  scope :with_everything, -> { with_attached.includes(:relevant_e6_posts, artist_submission: :artist_url) }

  scope :larger_iqdb_filesize_kb_exists, ->(threshold) { select_from_e6_posts_where_exists("size - ? > post_size and not post_is_deleted", threshold) }
  scope :larger_iqdb_filesize_percentage_exists, ->(threshold) { select_from_e6_posts_where_exists("size - (size / 100 * ?) > post_size and not post_is_deleted", threshold) }
  scope :smaller_iqdb_filesize_doesnt_exist, -> { select_from_e6_posts_where_not_exists("size <= post_size") }
  scope :larger_only_filesize_kb, ->(threshold) { larger_iqdb_filesize_kb_exists(threshold).smaller_iqdb_filesize_doesnt_exist.exact_match_doesnt_exist }
  scope :larger_only_filesize_percentage, ->(threshold) { larger_iqdb_filesize_percentage_exists(threshold).smaller_iqdb_filesize_doesnt_exist.exact_match_doesnt_exist }

  scope :larger_iqdb_dimensions_exist, -> { select_from_e6_posts_where_exists("width > post_width and height > post_height and not post_is_deleted") }
  scope :smaller_iqdb_dimensions_dont_exist, -> { select_from_e6_posts_where_not_exists("width <= post_width and height <= post_height") }
  scope :larger_only_dimensions, -> { larger_iqdb_dimensions_exist.smaller_iqdb_dimensions_dont_exist }

  scope :already_uploaded, -> { select_from_e6_posts_where_exists }
  scope :not_uploaded, -> { select_from_e6_posts_where_not_exists }
  scope :exact_match_exists, -> { select_from_e6_posts_where_exists("is_exact_match") }
  scope :exact_match_doesnt_exist, -> { select_from_e6_posts_where_not_exists("is_exact_match") }

  # avoid_posting and conditional_dnp never appear alone
  NON_ARTIST_TAGS = %w[unknown_artist unknown_artist_signature sound_warning epilepsy_warning].freeze

  scope :zero_sources, -> { joins(:relevant_e6_posts).where(relevant_e6_posts: { post_is_deleted: false }).where("jsonb_array_length(post_json->'sources') = 0") }
  scope :zero_artists, -> {
    artists_path = "post_json->'tags'->'artist'"
    artists_count = "jsonb_array_length(#{artists_path})"
    joins(:relevant_e6_posts).where(relevant_e6_posts: { post_is_deleted: false }).where("#{artists_count} = 0 or (#{artists_count} = 1 and #{artists_path}->>0 in (?))", NON_ARTIST_TAGS)
  }

  delegate :artist_url, :artist, to: :artist_submission

  def self.select_from_e6_posts_where_exists(condition = nil, *condition_args)
    where("exists (#{select_from_e6_posts(condition)})", *condition_args)
  end

  def self.select_from_e6_posts_where_not_exists(condition = nil, *condition_args)
    where("not exists (#{select_from_e6_posts(condition)})", *condition_args)
  end

  def self.select_from_e6_posts(condition)
    "select from e6_posts where submission_files.id = e6_posts.submission_file_id and e6_posts.similarity_score >= #{Config.similarity_cutoff} #{"and #{condition}" if condition}"
  end

  def self.blob_for_io(io, filename)
    # Deviantart doesn't have to return only images.
    # No way to find this out through the api response as far as I'm aware.
    # https://www.deviantart.com/fr95/art/779625010/
    mime_type = Marcel::MimeType.for io
    return if mime_type.in? Scraper::Submission::MIME_IGNORE

    ActiveStorage::Blob.create_and_upload!(io: io, filename: filename, content_type: mime_type, identify: false)
  end

  def self.from_attachable(attachable:, artist_submission:, url:, created_at:, file_identifier:)
    submission_file = SubmissionFile.new(
      artist_submission: artist_submission,
      direct_url: url,
      created_at_on_site: created_at,
      file_identifier: file_identifier,
    )
    case attachable
    when Tempfile
      submission_file.attach_original_from_file!(attachable)
    when ActiveStorage::Blob
      submission_file.attach_original_from_blob!(attachable)
    else
      raise ArgumentError, "'#{attachable.class}' is not supported"
    end
  end

  def attach_original_from_file!(file)
    filename = File.basename(Addressable::URI.parse(direct_url).path)
    blob = self.class.blob_for_io(file, filename)
    begin
      attach_original_from_blob!(blob) if blob
    rescue StandardError => e
      blob.purge
      raise e
    end
  end


  def attach_original_from_blob!(blob)
    blob.analyze
    raise(AnalysisError, "Failed to analyze") if blob.content_type == "application/octet-stream"
    raise(ContentTypeError, "'#{blob.content_type}' is not allowed") if blob.content_type.in?(Scraper::Submission::MIME_IGNORE)

    self.width = blob.metadata[:width]
    self.height = blob.metadata[:height]
    self.content_type = blob.content_type
    self.size = blob.byte_size

    if can_iqdb?
      begin
        Vips::Image.new_from_file(file_path_for(blob), fail: true).stats
      rescue Vips::Error => e
        self.file_error = e.message.strip
      end
    end

    original.attach(blob)
    save!
  end

  def corrupt?
    file_error.present?
  end

  def original_attachment=(new_attachment)
    super
    @original_purged = new_attachment.nil?
  end

  def original_present
    return if new_record? ? original.attached? : @original_purged != true

    errors.add(:original_file, "not attached")
  end

  def sample_generated?
    original.analyzed? && sample&.attached?
  end

  def md5
    base64_decoded = original.checksum.unpack1("m")
    base64_decoded.unpack1("H*")
  end

  def can_iqdb?
    IqdbProxy.can_iqdb?(content_type)
  end

  def update_variants_and_iqdb
    return if attachment_changes["original"].blank?

    SubmissionFileUpdateJob.perform_later(self)
  end

  def update_e6_posts(priority: E6IqdbQueryJob::PRIORITIES[:manual_action])
    e6_posts.destroy_all
    similar = IqdbProxy.query_submission_file(self).pluck(:submission_file)
    similar.each { |s| s.e6_posts.destroy_all }

    E6IqdbQueryJob.set(priority: priority).perform_later(self)
    similar.each do |s|
      # Process matches from other artists after everything else.
      # Chances are that they're just wrong iqdb matches.
      priority_for_similar = s.artist_submission.artist == artist_submission.artist ? priority : priority + 50
      E6IqdbQueryJob.set(priority: priority_for_similar).perform_later(s)
    end
  end

  def external_url
    "https://rfs.femboy.fan" + url_for(:original, disposition: :inline)
  end

  def update_e6_posts!
    e6_posts.destroy_all

    json = FemboyFansApiClient.iqdb_query(url: external_url)
    return unless json.is_a?(Array)

    json.each do |entry|
      post_entry = e6_posts.create(
        post_id: entry.dig("post", "id"),
        post_width: entry.dig("post", "file", "width"),
        post_height: entry.dig("post", "file", "height"),
        post_size: entry.dig("post", "file", "size"),
        post_is_deleted: entry.dig("post", "flags", "deleted"),
        post_json: entry["post"],
        similarity_score: entry["score"],
        is_exact_match: md5 == entry.dig("post", "file", "md5") || existing_matches(entry.dig("post", "id"), is_exact_match: true).any?,
      )

      # Check if there are entries which were previously added
      # that are an exact visual match to this newly added exact match
      if post_entry.is_exact_match
        existing_matches(entry.dig("post", "id"), is_exact_match: false).find_each do |existing_match|
          existing_match.update(is_exact_match: true)
        end
      end
    end
  end

  def existing_matches(post_id, is_exact_match:)
    E6Post.joins(:submission_file)
      .where(post_id: post_id, submission_file: { iqdb_hash: iqdb_hash }, is_exact_match: is_exact_match)
  end

  def remove_from_iqdb
    IqdbProxy.remove_submission self if can_iqdb?
  end

  def generate_variants
    io = VariantGenerator.sample(file_path_for(:original), content_type)
    sample.attach(io: io, filename: "sample")
  end

  def file_path_for(variant_or_blob)
    blob = variant_or_blob.is_a?(Symbol) ? send(variant_or_blob) : variant_or_blob
    blob.service.path_for(blob.key)
  end

  def url_for(variant, **)
    Rails.application.routes.url_helpers.rails_blob_path(send(variant), only_path: true, **)
  end

  concerning :SearchMethods do
    class_methods do
      def search(params)
        q = status_search(params)
        q = q.zero_sources if params[:zero_sources] == "1"
        q = q.zero_artists if params[:zero_artists] == "1"
        q = q.attribute_matches(params[:content_type], :content_type)
        q = q.attribute_nil_check(params[:in_backlog], :added_to_backlog_at)
        q = q.attribute_nil_check(params[:hidden_from_search] || false, :hidden_from_search_at)
        q = q.attribute_nil_check(params[:corrupt], :file_error)
        q = q.join_attribute_matches(params[:title], artist_submission: :title_on_site)
        q = q.join_attribute_matches(params[:description], artist_submission: :description_on_site)
        q = q.join_attribute_matches(params[:artist_url_id], artist_submission: { artist_url: :id })
        q = q.join_attribute_matches(params[:artist_id], artist_submission: { artist_url: { artist: :id } })
        q = q.join_attribute_matches(params[:site_type], artist_submission: { artist_url: :site_type })
        case params[:order]
        when "filesize_asc", "size_asc"
          q.order(size: :asc, created_at_on_site: :desc, file_identifier: :desc)
        when "filesize_desc", "filesize", "size_desc", "size"
          q.order(size: :desc, created_at_on_site: :desc, file_identifier: :desc)
        when "width_asc"
          q.order(width: :asc, created_at_on_site: :desc, file_identifier: :desc)
        when "width_desc", "width"
          q.order(width: :desc, created_at_on_site: :desc, file_identifier: :desc)
        when "height_asc"
          q.order(height: :asc, created_at_on_site: :desc, file_identifier: :desc)
        when "height_desc", "height"
          q.order(height: :desc, created_at_on_site: :desc, file_identifier: :desc)
        when "id_asc"
          q.order(id: :asc)
        when "id_desc", "id"
          q.order(id: :desc)
        else
          q.order(created_at_on_site: :desc, file_identifier: :desc)
        end
      end

      def status_search(params)
        if params[:upload_status].present?
          case params[:upload_status]
          when "larger_only_filesize_kb"
            size = (params[:larger_only_filesize_threshold] || 50).to_i.kilobytes
            send(params[:upload_status], size)
          when "larger_only_filesize_percentage"
            size = (params[:larger_only_filesize_threshold] || 10).to_i
            send(params[:upload_status], size)
          when "larger_only_dimensions", "exact_match_exists", "already_uploaded", "not_uploaded"
            send(params[:upload_status])
          else
            none
          end
        else
          all
        end
      end

      def search_params
        [:artist_id, :site_type, :upload_status, :corrupt, :zero_sources, :zero_artists, :larger_only_filesize_threshold, :content_type, :title, :description, { artist_url_id: [] }, :in_backlog, :order]
      end

      def pagy(params)
        params[:limit] ||= Config.files_per_page
        super
      end
    end
  end

  def similar # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    files = IqdbProxy.query_submission_file(self)
    notices = []
    files.each do |f|
      next if f[:score] < 80

      file = f[:submission_file]
      if file.width > width && file.height > height
        notices << { type: :larger, file: file }
      else
        notices << { type: :larger_width, file: file } if file.width > width
        notices << { type: :larger_height, file: file } if file.height > height
      end
      notices << { type: :different_type, file: file } if file.content_type != content_type
      notices << { type: :larger_filesize, file: file } if file.size > size
      notices << { type: :different_site, file: file } if file.artist_url.id != artist_url.id
    end

    largest_size = {}
    notices.each do |n|
      next if n[:type] != :larger_filesize

      s = n[:file].content_type.to_sym
      if largest_size[s].nil? || n[:file].size > largest_size[s]
        largest_size[s] = n[:file].size
        next
      end
    end

    notices.select { |n| n[:type] != :larger_filesize || largest_size[n[:file].content_type.to_sym] == n[:file].size }

    by_id = {}
    notices.each do |n|
      by_id[n[:file].id] ||= []
      by_id[n[:file].id] << n
    end

    by_id.values
  end

  def similar_text(sim, template)
    case sim[:type]
    when :larger
      "L"
    when :larger_width
      "LW"
    when :larger_height
      "LH"
    when :different_type
      "DT-#{Mime::Type.lookup(sim[:file].content_type).symbol.to_s.upcase}"
    when :larger_filesize
      "LF (#{template.number_to_human_size(sim[:file].size)})"
    when :different_site
      "DS"
    else
      "Unknown similarity type: :#{sim[:type]} for submission #{sim[:file].id}"
    end
  end

  NO_GALLERY_SITES = %w[twitter weasyl kemono manual].freeze

  def uploadable?
    direct_url.starts_with?("file://") || direct_url.include?("wixmp.com")
  end

  def upload_url(template) # rubocop:disable Metrics/CyclomaticComplexity
    # return nil unless e6_posts.empty?
    sources = []
    sources << template.gallery_url(artist_url) unless NO_GALLERY_SITES.include?(artist_url.site_type) || (artist.is_commissioner? && artist_url.site_type == "e621")
    sources << template.submission_url(artist_submission)
    file_url = uploadable? ? "" : "upload_url=#{CGI.escape(direct_url)}&"
    description = ""
    if artist_submission.description_on_site.present?
      clean = artist_submission.description_on_site.gsub("</p><p>", "\n\n").gsub(/(\A\s*<p>\s*)|(\s*<\/p>\s*\z)/, "")
      if artist_submission.title_on_site.blank?
        description = "[quote]\n#{clean}\n[/quote]"
      else
        description = "[section,expanded=#{artist_submission.title_on_site}]\n#{clean}\n[/section]"
      end
      description = "&description=#{CGI.escape(description)}"
    end
    tags = []
    extra = ""
    if artist.e621_tag.present?
      if artist_url.site_type == "e621"
        post = E6ApiClient.get_post_cached(artist_submission.identifier_on_site.to_i) rescue nil
        if artist.is_commissioner?
          extra += "&tags-artist=#{post['tags']['artist'].map { |t| "artist:#{t}" }.join("+")}" if post.present? && post['tags']['artist'].any?
          category = post["tags"].find { |_k, v| v.include?(artist.e621_tag) }.first
          if category && !%w[general].include?(category)
            tags << "#{category}:#{artist.e621_tag}"
          else
            tags << artist.e621_tag
          end
        else
          extra += "&tags-artist=artist:#{artist.e621_tag}"
        end
        if post["tags"]["character"].present?
          extra += "&tags-character=#{post['tags']['character'].map { |t| "character:#{t}" }.join("+")}"
        end
        if post["tags"]["species"].present?
          extra += "&tags-species=#{E6ApiClient.categorize_species_tags(post['tags']['species']).join("+")}"
        end
        if post["tags"]["meta"].present?
          year = post["tags"]["meta"].find { |v| %r{\A\d{4}\z}.match?(v) }
          tags << "meta:#{year}" if year
        end
        tags << "meta:#{created_at_on_site.year}" unless tags.any? { |t| t.start_with?("meta:") }
        sources += post["sources"].reject { |s| %w[png jpg jpeg webm webp gif mp4].any? { |ext| s.ends_with?(ext) } || %w[://pbs.twing.com].any? { |domain| s.include?(domain) } }
      else
        if artist.is_commissioner?
          tags << artist.e621_tag
        else
          extra += "&tags-artist=artist:#{artist.e621_tag}"
        end
        tags << "meta:#{created_at_on_site.year}"
      end

    end
    sources = sources.map { |source| CGI.escape(source) }.join(",")
    @upload_url ||= "https://femboy.fan/uploads/new?#{file_url}sources=#{sources}#{description}&tags=#{tags.join('+')}#{extra}"
  end

  def replacement_url(template, entry)
    return unless uploadable?
    @replacement_url ||= "https://femboy.fan/posts/replacements/new?post_id=#{entry.post_id}&upload_url=#{CGI.escape(direct_url)}&additional_source=#{CGI.escape(template.submission_url(artist_submission))}"
  end

  def iqdb_similar
    return IqdbProxy.query_submission_file(self) if can_iqdb? && sample_generated?
    []
  end

  def self.find_by_md5(md5)
    SubmissionFile.joins(original_attachment: :blob).find_by(active_storage_blobs: { checksum: Base64.encode64([md5].pack("H*"))[..-2] })
  end
end
