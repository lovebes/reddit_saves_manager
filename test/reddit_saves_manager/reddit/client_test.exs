defmodule RedditSavesManager.Reddit.ClientTest do
  # async: false — this test stubs Req via a global Application env key
  # (:reddit_req_options), which every other test file touching the Reddit
  # client also mutates. Running those concurrently races on that shared,
  # process-independent state, so every test file that sets
  # :reddit_req_options or :open_router_req_options in this plan uses
  # async: false for the same reason.
  use ExUnit.Case, async: false
  alias RedditSavesManager.Reddit.Client

  setup do
    Application.put_env(:reddit_saves_manager, :reddit_req_options, plug: {Req.Test, Client})

    :ok
  end

  test "authorize_url/1 builds a reddit authorize URL with the given state" do
    url = Client.authorize_url("xyz")
    assert url =~ "https://www.reddit.com/api/v1/authorize"
    assert url =~ "state=xyz"
  end

  test "exchange_code/1 returns access/refresh tokens on success" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => "atok",
        "refresh_token" => "rtok",
        "expires_in" => 3600
      })
    end)

    assert {:ok, %{access_token: "atok", refresh_token: "rtok", expires_in: 3600}} =
             Client.exchange_code("some-code")
  end

  test "refresh_token/1 returns a new access token" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{"access_token" => "newtok", "expires_in" => 3600})
    end)

    assert {:ok, %{access_token: "newtok", expires_in: 3600}} = Client.refresh_token("rtok")
  end
end
