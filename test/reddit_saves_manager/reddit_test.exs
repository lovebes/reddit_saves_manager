defmodule RedditSavesManager.RedditTest do
  # async: false — the refresh-failure test below stubs Req via the shared
  # :reddit_req_options Application env key (see the note in
  # reddit/client_test.exs).
  use RedditSavesManager.DataCase, async: false
  alias RedditSavesManager.Reddit
  alias RedditSavesManager.Reddit.Client

  test "save_token/1 then valid_access_token/0 returns the stored token when not expired" do
    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      Reddit.save_token(%{access_token: "atok", refresh_token: "rtok", expires_at: future})

    assert {:ok, "atok"} = Reddit.valid_access_token()
  end

  test "valid_access_token/0 returns :not_authenticated when no token stored" do
    assert {:error, :not_authenticated} = Reddit.valid_access_token()
  end

  test "valid_access_token/0 returns :not_authenticated when the stored token is expired and refresh fails" do
    Application.put_env(:reddit_saves_manager, :reddit_req_options, plug: {Req.Test, Client})

    Req.Test.stub(Client, fn conn ->
      Plug.Conn.send_resp(conn, 400, Jason.encode!(%{"error" => "invalid_grant"}))
    end)

    past = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      Reddit.save_token(%{access_token: "stale", refresh_token: "deadrtok", expires_at: past})

    assert {:error, :not_authenticated} = Reddit.valid_access_token()
  end
end
