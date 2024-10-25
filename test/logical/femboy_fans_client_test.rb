require "test_helper"

class FemboyFansApiClientTest < ActiveSupport::TestCase
  test "get_post" do
    stub_request_once(:get, "#{FemboyFansApiClient::ORIGIN}/posts/1.json", body: { id: 1 }.to_json, headers: { content_type: "application/json" })
    assert_equal(1, FemboyFansApiClient.get_post(1)["id"])
  end
end
