module Scraper
  class Kemono < Base
    STATE = :offset
    SERVERS = %w[https://n1.kemono.cr https://n2.kemono.cr https://n3.kemono.cr https://n4.kemono.cr].freeze
    HASH_LENGTH = 64

    def initialize(artist_url)
      super
      @offset = 0
    end

    def fetch_next_batch
      response = make_request("/api/v1/patreon/user/#{url_identifier}/posts", {
        o: @offset,
      })
      end_reached if response.size < 50
      @offset = @offset.to_i + 50
      response
    end

    def to_submission(indexpost)
      sub = ArtistSubmission.joins(:artist_url).find_by(identifier_on_site: indexpost["id"], "artist_urls.url_identifier": url_identifier)
      s = Submission.new
      files = []
      if sub
        s.identifier = sub.identifier_on_site
        s.title = sub.title_on_site
        s.description = sub.description_on_site
        s.created_at = sub.created_at_on_site
        files += [indexpost["file"], *indexpost["attachments"]].uniq.compact_blank
      else
        submission = fetch_post(indexpost["id"])["post"]
        s.identifier = submission["id"]
        s.title = submission["title"]
        s.description = submission["content"]
        s.created_at = DateTime.parse(submission["published"])
        files += [submission["file"], *submission["attachments"]].uniq.compact_blank
      end

      files.each do |file|
        path = file["path"].gsub(" ", "%20")
        server = get_server(path)
        next if server.nil?

        s.add_file({
          url: "#{server}/data#{path}?f=#{file['name']}",
          created_at: s.created_at,
          identifier: file["path"][7, HASH_LENGTH],
        })
      end

      s
    end

    def fetch_api_identifier
      url_identifier
    end

    def extend_client(client)
      client
        .with(headers: { "User-Agent": FRIENDLY_USER_AGENT, "Accept": "text/css" }, origin: "https://kemono.cr")
    end

    private

    def make_request(url, params = {})
      client.fetch_json(url, params: params)
    end

    def get_server(path)
      return "https://img.kemono.cr/thumbnail" if path.start_with?("/attachments")
      file = SubmissionFile.joins(artist_submission: :artist_url).find_by(file_identifier: path[7, HASH_LENGTH], "artist_urls.url_identifier": url_identifier)
      if file&.direct_url
        srv = SERVERS.find { |s| file.direct_url.start_with?(s) }
        return srv if srv
      end

      SERVERS.each do |server|
        response = client.head("#{server}/data#{path}", should_raise: false, should_log: false)
        return server if response.status == 200
        case response.status
        when 200
          return server
        when 302
          loc = response.headers.get("location")
          srv = SERVERS.find { |s| loc.any? { |l| l.start_with?(s) } }
          return srv if srv
          raise("Got 302 to unexpected location \"#{loc.size == 1 ? loc.first : loc.inspect}\" for #{path} on #{server}")
        when 403
          next # ignore
        else
          raise("Found server #{server} for #{path}, but it seems to not be working: #{response.status}")
        end
      end

      raise("Could not find server for #{path}")
    end

    def fetch_post(id)
      make_request("/api/v1/patreon/user/#{url_identifier}/post/#{id}")
    end
  end
end
