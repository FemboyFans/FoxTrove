module E6ApiClient
  ORIGIN = "https://e621.net"
  TAGS_ORIGIN = "https://e621-tags.furry.cool"
  extend self

  def iqdb_query(file)
    # FIXME: Proper rate limiting
    sleep 2 unless Rails.env.test?
    client.post("/iqdb_queries.json", form: { file: file }).raise_for_status.json
  end

  def get_post(id)
    client.get("/posts/#{id}.json").raise_for_status.json["post"]
  end

  def get_post_cached(id)
    Rails.cache.fetch("e6post:#{id}", expires_in: 7.days) do
      get_post(id)
    end
  end

  def get_posts(tags, page: 1, limit: 320)
    tags = [tags] unless tags.is_a?(Array)
    client.get("/posts.json?tags=#{tags.join('%20')}&page=#{page}&limit=#{limit}").raise_for_status.json["posts"]
  end

  def get_posts_cached(ids)
    uncached = ids.reject { |id| Rails.cache.exist?("e6post:#{id}") }
    posts = []
    uncached.each_slice(100) do |slice|
      posts += E6ApiClient.get_posts(%W[id:#{slice.join(',')} status:any], limit: 100).compact_blank
    end
    posts.each do |post|
      Rails.cache.write("e6post:#{post['id']}", post, expires_in: 7.days)
    end
    ids.map { |id| Rails.cache.read("e6post:#{id}") }
  end

  def get_all_posts(tags)
    fetch = ->(page) {
      d = get_posts(tags, page: page)
      if d.length == 320
        d += fetch.call(page + 1)
      end
      d
    }
    fetch.call(1)
  end

  def get_replacements(id: nil, md5: nil, post_id: nil, status: nil)
    url = "/post_replacements.json?"
    url += "search[id]=#{id}&" if id
    url += "search[md5]=#{md5}&" if md5
    url += "search[post_id]=#{post_id}&" if post_id
    url += "search[status]=#{status}&" if status
    client.get(url).raise_for_status.json
  end

  def get_unimplied_tags(tags)
    tags = tags.join(" ") if tags.is_a?(Array)
    key = "uitags:#{tags.gsub(' ', '_')}"
    return Rails.cache.read(key) if Rails.cache.exist?(key)
    list = tags_client.get("/get?tags=#{tags}&basic=true").raise_for_status.json["tags"]
    Rails.cache.write(key, list, expires_in: 30.days)
    list
  end

  private

  def client
    @client ||= HTTPX
      .plugin(:basic_auth)
      .basic_auth(Config.e621_user, Config.e621_apikey)
      .with(origin: ORIGIN, headers: { "user-agent" => Scraper::Base::FRIENDLY_USER_AGENT })
  end

  def tags_client
    @tags_client ||= HTTPX
      .with(origin: TAGS_ORIGIN, headers: { "user-agent" => Scraper::Base::FRIENDLY_USER_AGENT })
  end
end
