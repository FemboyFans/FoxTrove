module Scraper
  class Patreon < Base
    STATE = :date
    DOMAIN = "patreon.com"
    OPTIONAL_CONFIG_KEYS = %i[patreon_otp_secret patreon_proxy].freeze

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
      raw.select { |s| s.last["current_user_can_view"] == true }.group_by { |s| s.last["id"] }.values
    end

    def with_cookies
      Tempfile.create(%W[patreon-cookies-#{@artist_url.id}- .txt]) do |file|
        *, session_cookie = fetch_cookie
        file.write("#{session_cookie}\n")
        file.flush
        yield(file)
      end
    end

    def to_submission(submission)
      post = submission.find { |s| s.length == 2 }.second
      images = submission.select { |s| s.length == 3 }
      s = Submission.new
      s.identifier = post["id"]
      s.title = post["title"]
      s.description = post["content"] || ""
      s.created_at = DateTime.parse post["date"]

      images.each do |(_index, url, img)|
        s.add_file({
                     url: url,
                     url_data: [img["id"], img.dig("file", "display", "media_id")],
                     url_expires_at: parse_url_expiry(url),
                     created_at: s.created_at,
                     identifier: img.dig("file", "file_name") || "#{img['hash']}-#{File.basename(URI.parse(url).path)}",
                   })
      end
      s
    end

    def get_download_url(data)
      raw = make_request("/posts/#{data[0]}", filter: false)
      url = raw.find { |s| s.length == 3 && s[2].dig("file", "display", "media_id") == data[1] }.try(:[], 1)
      return nil if url.nil?
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

    private

    def make_request(path, filter: true)
      with_cookies do |file|
        proxy = "--proxy", Config.patreon_proxy if Config.patreon_proxy.present?
        filterargs = "--filter", "date >= datetime(#{@date.year}, #{@date.month}, #{@date.day}, #{@date.hour}, #{@date.minute}, #{@date.second}) or abort()" if filter
        command = "gallery-dl", "-J", "--cookies", file.path, *filterargs, *proxy, "https://#{self.class::DOMAIN}#{path}"
        stdout, stderr, status = Open3.capture3(*command)
        @artist_url.add_log_event(:gallery_dl, {
          date: @date.iso8601,
          url: "https://#{self.class::DOMAIN}#{path}",
          command: command,
        })
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

    def parse_url_expiry(url)
      DateTime.strptime(Rack::Utils.parse_nested_query(URI.parse(url).query)["token-time"], "%s") rescue nil
    end

    def fetch_cookie
      SeleniumWrapper.driver do |driver|
        driver.navigate.to "https://#{self.class::DOMAIN}/login"

        driver.wait_for_element(css: "input[name=email]").send_keys Config.patreon_user
        driver.find_element(css: "button[type=submit]").click
        driver.wait_for_element_displayed(css: "input[name=current-password]").send_keys Config.patreon_pass
        driver.find_element(css: "button[type=submit]").click

        if Config.patreon_otp_secret.present?
          otp = ROTP::TOTP.new(Config.patreon_otp_secret).now
          driver.wait_for_element(css: "input[name=one-time-code]").send_keys otp
          driver.find_element(css: "button[type=submit]").click
        end

        name = "session_id"
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
  end
end
