FactoryBot.define do
  factory :femboyfans_post_response, parent: :json do
    post_id { nil }
    md5 { nil }

    json do
      {
        id: post_id,
        file: {
          width: 10,
          height: 10,
          size: 10.kilobytes,
          md5: md5,
        },
        flags: {
          deleted: false,
        },
        sample: {
          url: "https://static1.femboy.fan/data/#{md5[0..1]}/#{md5[2..3]}/#{md5}.png",
        },
      }
    end
  end
end
