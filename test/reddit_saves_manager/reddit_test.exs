defmodule RedditSavesManager.RedditTest do
  use RedditSavesManager.DataCase
  alias RedditSavesManager.Reddit

  test "save_token/1 then valid_access_token/0 returns the stored token when not expired" do
    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      Reddit.save_token(%{access_token: "atok", refresh_token: "rtok", expires_at: future})

    assert {:ok, "atok"} = Reddit.valid_access_token()
  end

  test "valid_access_token/0 returns :not_authenticated when no token stored" do
    assert {:error, :not_authenticated} = Reddit.valid_access_token()
  end
end
