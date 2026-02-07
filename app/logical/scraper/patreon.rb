module Scraper
  class Patreon < Base
    STATE = :date
    DOMAIN = "patreon.com"
    OPTIONAL_CONFIG_KEYS = %i[patreon_otp_secret patreon_proxy].freeze

    def initialize(artist_url)
      super
      @date = Time.zone.at(0).to_datetime
    end

    def fetch_next_batch
      result = with_cookies do |file|
        proxy = "--proxy", Config.patreon_proxy if Config.patreon_proxy.present?
        command = "gallery-dl", "-J", "--cookies", file.path, "--filter", "date >= datetime(#{@date.year}, #{@date.month}, #{@date.day}, #{@date.hour}, #{@date.minute}, #{@date.second}) or abort()", *proxy, "https://#{self.class::DOMAIN}/#{url_identifier}"
        stdout, stderr, status = Open3.capture3(*command)
        @artist_url.add_log_event(:gallery_dl, {
          date: @date.iso8601,
          url: "https://#{self.class::DOMAIN}/#{url_identifier}",
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
        recent = raw.max { |a, b| DateTime.parse(b.last["date"]) - DateTime.parse(a.last["date"]) }
        @date = DateTime.parse(recent.last["date"]) if recent&.last
        # first is an arbitrary index, second is a url (possibly absent), last is the actual post
        # each post will have at least two individual entries, the first is the post and the rest are the images
        raw.select { |s| s.last["current_user_can_view"] == true }.group_by { |s| s.last["id"] }.values
      end
      end_reached
      result
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
                     created_at: s.created_at,
                     identifier: img["file"]["file_name"],
                   })
      end
      s
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

    protected

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
