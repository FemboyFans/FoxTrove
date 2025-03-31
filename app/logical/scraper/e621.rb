module Scraper
  class E621 < Base
    STATE = :after

    def initialize(artist_url)
      super
      @after = 0
    end

    def fetch_next_batch
      response = make_request("/posts.json", {
        page: "a#{@after}",
        limit: 320,
        tags: url_identifier,
      })
      @after = response["posts"].first.try(:[], "id")
      end_reached if response["posts"].size < 320
      response["posts"]
    end

    def to_submission(submission)
      s = Submission.new
      s.identifier = submission["id"]
      s.title = ""
      s.description = submission["description"]
      s.created_at = DateTime.parse submission["created_at"]

      s.add_file({
        url: submission["file"]["url"],
        created_at: s.created_at,
        identifier: submission["file"]["md5"],
      })
      s
    end

    def fetch_api_identifier
      url_identifier
    end

    def extend_client(client)
      client
        .plugin(:basic_auth)
        .with(headers: { "User-Agent": FRIENDLY_USER_AGENT }, origin: "https://e621.net")
    end

    private

    def make_request(url, params = {})
      with_basic_auth = client.basic_auth(Config.e621_user, Config.e621_apikey)
      with_basic_auth.fetch_json(url, params: params)
    end
  end
end
