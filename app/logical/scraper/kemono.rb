module Scraper
  class Kemono < Base
    STATE = :offset

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
           url: "https://n1.kemono.su/data#{file['path']}?f=#{file['name']}",
           created_at: s.created_at,
           identifier: file["path"][8..file["path"].index(".").to_i - 1],
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
  end
end
