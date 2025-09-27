FactoryBot.define do
  factory :e6_post_response, parent: :json do
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
          url: "https://static.femboy.fan/data/#{md5[0..1]}/#{md5[2..3]}/#{md5}.png",
        },
        flags: {
          deleted: false,
        },
        variants: [
          {
            ext: "png",
            md5: md5,
            size: 10.kilobytes,
            type: "large",
            video: false,
            width: 10,
            height: 10,
            url: "https://static.femboy.fan/data/#{md5[0..1]}/#{md5[2..3]}/#{md5}.png"
          }
        ]
      }
    end
  end
end
