module FemboyFansApiClient
  ORIGIN = "https://femboy.fan"
  extend self

  def iqdb_query(file: nil, url: nil)
    if file
      client.post("/posts/iqdb.json", form: { file: file }).raise_for_status.json
    elsif url
      client.post("/posts/iqdb.json", form: { url: url }).raise_for_status.json
    else
      raise(ArgumentError, "either file or url must be provided")
    end
  end

  def get_post(id)
    client.get("/posts/#{id}.json").raise_for_status.json
  end

  def get_posts(tags, page: 1, limit: 500)
    tags = [tags] unless tags.is_a?(Array)
    client.get("/posts.json?tags=#{tags.join('%20')}&page=#{page}&limit=#{limit}").raise_for_status.json
  end

  def get_all_posts(tags)
    fetch = ->(page) {
      d = get_posts(tags, page: page)
      if d.length == 500
        d += fetch.call(page + 1)
      end
      d
    }
    fetch.call(1)
  end

  private

  def client
    @client ||= HTTPX
      .plugin(:basic_auth)
      .basic_auth(Config.femboyfans_user, Config.femboyfans_apikey)
      .with(origin: ORIGIN, headers: { "user-agent" => Scraper::Base::FRIENDLY_USER_AGENT })
  end
end
