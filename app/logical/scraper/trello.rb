module Scraper
  class Trello < Base
    STATE = :before

    def initialize(artist_url)
      super
      @before = nil
    end

    def fetch_next_batch
      url = "https://api.trello.com/1/boards/#{api_identifier}/cards"
      json = fetch_json(url,
                        params: {
                                  attachments: true,
                                  attachment_fields: "id,date,url",
                                  fields: "id,desc,shortLink,name",
                                  limit: 1000,
                                  sort: "-id"
                                }.tap { |h| h[:before] = @before if @before },
                        )
      @before = json.sort_by { |c| c["id"][0..7].to_i(16) }.first.try(:[], "id")
      end_reached if json.length < 1000
      json.select { |c| c["attachments"].length > 0}
    end

    def to_submission(submission)
      s = Submission.new
      s.identifier = submission["shortLink"]
      s.title = submission["name"]
      s.description = submission["desc"]
      s.created_at = Time.at(submission["id"][0..7].to_i(16)).to_datetime

      submission["attachments"].each do |entry|
        s.add_file({
         url: entry["url"],
         created_at: DateTime.parse(entry["date"]),
         identifier: entry["id"],
       })
      end
      s
    end

    # Unfortunately the api doesn't seem to return this information
    def fetch_api_identifier
      url = "https://trello.com/b/#{url_identifier}.json"
      json = fetch_json(url, params: {
        actions: "none",
        cards: "none",
        fields: "id",
        labels: "none",
        lists: "none"
      })
      json["id"]
    end
  end
end
