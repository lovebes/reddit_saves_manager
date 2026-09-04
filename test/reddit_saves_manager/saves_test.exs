defmodule RedditSavesManager.SavesTest do
  # async: false — Task 9 appends a test to this file that stubs Req via the
  # shared :reddit_req_options Application env key (see the note in
  # reddit/client_test.exs), so the whole file must run non-concurrently.
  use RedditSavesManager.DataCase, async: false

  alias RedditSavesManager.Saves

  @valid_attrs %{
    reddit_fullname: "t3_abc123",
    type: "link",
    title: "Some post",
    subreddit: "elixir",
    permalink: "/r/elixir/comments/abc123/some_post/",
    saved_at: ~U[2026-01-01 00:00:00Z]
  }

  test "upsert_saved_post/1 inserts a new post" do
    assert {:ok, post} = Saves.upsert_saved_post(@valid_attrs)
    assert post.reddit_fullname == "t3_abc123"
  end

  test "upsert_saved_post/1 updates on duplicate reddit_fullname" do
    {:ok, _} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, updated} = Saves.upsert_saved_post(Map.put(@valid_attrs, :score, 42))
    assert updated.score == 42
    assert Saves.list_active_posts() |> length() == 1
  end

  test "list_active_posts/0 excludes archived posts" do
    {:ok, post} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, _} = Saves.archive_posts([post.id])
    assert Saves.list_active_posts() == []
  end
end
