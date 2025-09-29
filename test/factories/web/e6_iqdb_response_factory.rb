FactoryBot.define do
  factory :e6_iqdb_response, parent: :json do
    post_ids { [] }
    md5 { "0" * 32 }

    json do
      post_ids.map do |iqdb_match_id|
        {
          score: 90,
          post: {
            id: iqdb_match_id,
            file: {
              width: 10,
              height: 10,
              size: 10.kilobytes,
              md5: md5,
            },
            flags: {
              deleted: false,
            },
          },
        }
      end
    end
  end
end
