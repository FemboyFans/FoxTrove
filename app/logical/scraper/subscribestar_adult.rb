module Scraper
  class SubscribestarAdult < Subscribestar
    DOMAIN = "subscribestar.adult"

    def self.all_config_keys
      Subscribestar.all_config_keys - %i[subscribestar_disabled?] + %i[subscribestar_adult_disabled?]
    end

    def with_cookies
      Tempfile.create(%W[subscribestar-adult-cookies-#{@artist_url.id}- .txt]) do |file|
        *, personalization_cookie = fetch_cookie
        age_check_cookie = format_cookie({
          domain: "subscribestar.adult",
          http_only: false,
          secure: true,
          expires: 0,
          path: "/",
          name: "18_plus_agreement_generic",
          value: "true",
        })
        file.write("#{personalization_cookie}\n")
        file.write("#{age_check_cookie}\n")
        file.flush
        yield(file)
      end
    end
  end
end
