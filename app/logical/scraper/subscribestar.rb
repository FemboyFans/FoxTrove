module Scraper
  class Subscribestar < Base
    STATE = :date
    DOMAIN = "subscribestar.com"
    OPTIONAL_CONFIG_KEYS = %i[subscribestar_otp_secret].freeze

    def self.all_config_keys
      super - %i[subscribestar_adult_disabled?]
    end

    def initialize(artist_url)
      super
      @date = artist_url.last_scraped_at&.to_datetime || Time.zone.at(0).to_datetime
    end

    def fetch_next_batch
      raw = make_request("/#{url_identifier}", filter: true)
      recent = raw.max { |a, b| DateTime.parse(b.last["date"]) - DateTime.parse(a.last["date"]) }
      @date = DateTime.parse(recent.last["date"]) if recent&.last
      end_reached
      # first is an arbitrary index, second is a url (possibly absent), last is the actual post
      # each post will have at least two individual entries, the first is the post and the rest are the images
      raw.group_by { |s| s.last["post_id"] }.values
    end

    def with_cookies
      Tempfile.create(%W[subscribestar-cookies-#{@artist_url.id}- .txt]) do |file|
        *, personalization_cookie = fetch_cookie
        file.write("#{personalization_cookie}\n")
        file.flush
        yield(file)
      end
    end

    def make_request(path, filter: true)
      with_cookies do |file|
        filterargs = "--filter", "date >= datetime(#{@date.year}, #{@date.month}, #{@date.day}, #{@date.hour}, #{@date.minute}, #{@date.second}) or abort()" if filter
        command = "gallery-dl", "-J", "--cookies", file.path, *filterargs, "https://#{self.class::DOMAIN}#{path}"
        @artist_url.add_log_event(:gallery_dl, {
          date: @date.iso8601,
          url: "https://#{self.class::DOMAIN}#{path}",
          command: command,
        })
        stdout, stderr, status = Open3.capture3(*command)
        if status.exitstatus != 0
          raise(StandardError, stderr)
        end

        raw = JSON.parse(stdout.strip)
        if raw.length == 1 && raw.first.second.is_a?(Hash) && raw.first.second.key?("error")
          Rails.logger.error(stderr)
          raise("#{raw.first.second['error']}: #{raw.first.second['message']}")
        end
        raw
      end
    end

    def to_submission(submission)
      post = submission.find { |s| s.length == 2 }.second
      images = submission.select { |s| s.length == 3 }
      s = Submission.new
      s.identifier = post["post_id"]
      s.title = ""
      s.description = post["content"]
      s.created_at = DateTime.parse(post["date"])

      images.each do |(_index, url, img)|
        url = resolve_url(url)
        s.add_file({
          url: url,
          url_expires_at: parse_url_expiry(url),
          url_data: [img["post_id"], img["id"]],
          created_at: DateTime.parse(img["date"]),
          identifier: img["id"],
        })
      end
      s
    end

    def get_download_url(data)
      raw = make_request("/posts/#{data[0]}", filter: false)
      url = raw.find { |s| s.length == 3 && s[2]["id"] == data[1] }.try(:[], 1)
      return nil if url.nil?
      url = resolve_url(url)
      [url, parse_url_expiry(url)]
    end

    def fetch_api_identifier
      url_identifier
    end

    def extend_client(client)
      client
        .with(headers: { "User-Agent": FRIENDLY_USER_AGENT }, origin: self.class::DOMAIN)
    end

    def jumpstart(value)
      super(DateTime.parse(value))
    end

    def download_headers
      personalization_id, = fetch_cookie
      { Cookie: "_personalization_id=#{personalization_id}" }
    end

    protected

    def parse_url_expiry(url)
      uri = URI.parse(url)
      params = Rack::Utils.parse_nested_query(uri.query)
      resources = JSON.parse(Base64.decode64(params["Policy"].gsub("~", "/")))["Statement"]
      return DateTime.strptime(resources.first.dig("Condition", "DateLessThan", "AWS:EpochTime").to_s, "%s") if resources.length == 1
      expected = uri.dup
      expected.query = "filename=#{params['filename']}"
      res = resources.find { |r| r["Resource"] == expected.to_s }
      return nil if res.nil?
      DateTime.strptime(res.dig("Condition", "DateLessThan", "AWS:EpochTime").to_s, "%s")
    end

    def fetch_cookie
      SeleniumWrapper.driver do |driver|
        driver.navigate.to "https://#{self.class::DOMAIN}/login"

        driver.wait_for_element(css: "div.login input[name='email']").send_keys Config.subscribestar_user
        driver.find_element(css: "button.for-login[type=submit]").click
        driver.wait_for_element(css: "div.login input[name='password']").send_keys Config.subscribestar_pass
        driver.find_element(css: "button.for-login[type=submit]").click

        if Config.subscribestar_otp_secret.present?
          otp = ROTP::TOTP.new(Config.subscribestar_otp_secret).now
          driver.wait_for_element(css: "div.login input[name='code']").send_keys otp
          driver.find_element(css: "button.for-login[type=submit]").click
        end

        name = "_personalization_id"
        driver.wait_for_cookie(name)
        cookie = driver.manage.cookie_named(name)
        [cookie[:value], format_cookie(cookie)]
      end
    rescue StandardError => e
      Rails.logger.error("Selenium error: #{e.class} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise(e)
    end
    cache(:fetch_cookie, 4.weeks)

    def format_cookie(cookie)
      "#{cookie[:domain]}\t#{cookie[:http_only].to_s.upcase}\t#{cookie[:path]}\t#{cookie[:secure].to_s.upcase}\t#{cookie[:expires].to_i}\t#{cookie[:name]}\t#{cookie[:value]}"
    end

    def resolve_url(url)
      return url unless URI.parse(url).path == "/post_uploads"
      res = client.request("HEAD", url, headers: download_headers, should_raise: false)
      return url if res.status == 200
      return res.headers["location"] if res.status == 302
      res.raise_unless_ok
    end
  end
end
