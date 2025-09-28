module Scraper
  class Kemono < Base
    STATE = :offset
    SERVERS = %w[https://n1.kemono.cr https://n2.kemono.cr https://n3.kemono.cr https://n4.kemono.cr]
    HASH_LENGTH = 64

    def initialize(artist_url)
      super
      @offset = 0
    end

    def fetch_next_batch
      response = make_request("/api/v1/patreon/user/#{url_identifier}", {
        o: @offset
      })
      end_reached if response.size < 50
      @offset = @offset.to_i + 50
      response
    end

    def to_submission(submission)
      s = Submission.new
      s.identifier = submission["id"]
      s.title = submission["title"]
      s.description = submission["content"]
      s.created_at = DateTime.parse submission["published"]
      files = [submission["file"], *submission["attachments"]].uniq.compact_blank

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
      SERVERS.each do |server|
        response = client.head("#{server}/data#{path}", should_raise: false, should_log: false)
        return server if response.status == 200
        unless response.status == 403
          raise(RuntimeError, "Found server #{server} for #{path}, but it seems to not be working: #{response.status}")
        end
      end

      raise(RuntimeError, "Could not find server for #{path}")
    end
  end
end
