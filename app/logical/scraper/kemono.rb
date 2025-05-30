module Scraper
  class Kemono < Base
    STATE = :offset
    SERVERS = %w[https://n1.kemono.su https://n2.kemono.su https://n3.kemono.su https://n4.kemono.su]
    HASH_LENGTH = 64

    def initialize(artist_url)
      super
      @offset = nil
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
        s.add_file({
           url: "#{get_server(file['path'])}/data#{file['path']}?f=#{file['name']}",
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
        .with(headers: { "User-Agent": FRIENDLY_USER_AGENT }, origin: "https://kemono.su")
    end

    private

    def make_request(url, params = {})
      client.fetch_json(url, params: params)
    end

    def get_server(path)
      SERVERS.each do |server|
        response = client.head("#{server}/data#{path}", should_raise: false, should_log: false)
        return server if response.status == 200
      end

      raise(RuntimeError, "Could not find server for #{path}")
    end
  end
end
