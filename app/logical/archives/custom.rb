module Archives
  class Custom < Base
    def self.handles_file(file)
      Zip::File.open(file) do |zip_file|
        zip_file.glob("**/details.csv").any?
      end
    end

    def import_submission_files(artist_id, _source_url)
      raise ArgumentError, "Artist id must be set" if artist_id.blank?

      artist_url = ArtistUrl.find_or_create_by!(site_type: "manual", artist_id: artist_id) do |url|
        url.url_identifier = "manual-#{artist_id}"
        url.created_at_on_site = Time.current
        url.about_on_site = ""
      end

      Zip::File.open(@file) do |zip_file|
        zip_file.glob("**/details.csv").each do |entry|
          dir = File.dirname(entry.name)
          details = CSV.parse(entry.get_input_stream.read, headers: true)
          import_directory(artist_url, zip_file, details, dir)
        end
      end
    end

    def import_directory(artist_url, zip, details, dir)
      details.each_with_index do |row, index|
        file = row["file"]
        url = row["url"].presence || file
        date = Time.parse(row["date"] || Time.current.iso8601).utc
        title = row["title"] || ""
        description = row["description"] || ""
        path = File.join(dir, file)
        entry = zip.find_entry(path)
        raise ArgumentError, "File name must be set: #{dir}|#{index + 1}" if file.blank?
        raise ArgumentError, "File not found in archive: #{dir}|#{file}|#{index + 1}" if entry.nil?

        artist_submission = ArtistSubmission.find_or_create_by!(artist_url: artist_url, identifier_on_site: url) do |submission|
          submission.title_on_site = title
          submission.description_on_site = description
          submission.created_at_on_site = date
        end

        import_file(artist_url, artist_submission, entry)
      end
    end

    def import_file(artist_url, artist_submission, entry)
      if SubmissionFile.joins(artist_submission: :artist_url).where("artist_urls.id": artist_url.id).exists?("submission_files.file_identifier": entry.name)
        @already_imported_count += 1
      else
        super(artist_submission, entry)
      end
    end
  end
end
