# frozen_string_literal: true

module Scraper
  # This is unnecessarily convoluted. Let's hope Sofurry Next will actually happen sometime
  # https://wiki.sofurry.com/wiki/SoFurry_2.0_API
  # https://wiki.sofurry.com/wiki/How_to_use_OTP_authentication
  class Sofurry < Base
    def init
      @page = 1
      @otp_sequence = 0
      @otp_pad = ""
      @otp_salt = ""
      @request_retries = 0
      @previous_ids = []
    end

    def self.enabled?
      Config.sofurry_user.present? && Config.sofurry_pass.present?
    end

    def fetch_next_batch
      json = make_request "https://api2.sofurry.com/browse/user/art", "uid": api_identifier, "art-page": @page, "format": "json"
      items = json["items"]
      ids = items.pluck("id")
      # API always returns 30 items, could also use that to check, though I'm not sure if that will always be the case.
      # I don't trust this API at all. This will make one extra request, just to make sure.
      if ids == @previous_ids
        end_reached
        []
      else
        @previous_ids = ids
        @page += 1
        json["items"]
      end
    end

    def to_submission(submission)
      s = Submission.new
      s.identifier = submission["id"]
      s.title = submission["title"]
      s.description = Rails::Html::FullSanitizer.new.sanitize(submission["description"]) || ""
      s.created_at = DateTime.strptime(submission["postTime"], "%s")

      s.add_file({
        url: "https://www.sofurryfiles.com/std/content?page=#{submission['id']}",
        created_at: s.created_at,
        identifier: "",
      })
      s
    end

    def fetch_api_identifier
      user_json = make_request "https://api2.sofurry.com/std/getUserProfile", username: url_identifier
      return nil unless user_json["useralias"]&.casecmp? url_identifier

      user_json["userID"]
    end

    private

    def make_request(url, **query)
      while true
        password_hash = Digest::MD5.hexdigest "#{Config.sofurry_pass}#{@otp_salt}"
        otp_hash = Digest::MD5.hexdigest "#{password_hash}#{@otp_pad}#{@otp_sequence}"
        response = fetch_json(url, query: {
          otpuser: Config.sofurry_user,
          otphash: otp_hash,
          otpsequence: @otp_sequence,
          **query,
        })
        if response["messageType"] != 6
          @request_retries = 0
          @otp_sequence += 1
          return response
        end
        @request_retries += 1
        raise StandartError, "failed to authenticate" if @request_retries > 5

        @otp_sequence = response["newSequence"]
        @otp_pad = response["newPadding"]
        @otp_salt = response["salt"]
      end
    end
  end
end
