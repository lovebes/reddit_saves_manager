defmodule RedditSavesManager.SavesTest do
  # async: false — Task 9 appends a test to this file that stubs Req via the
  # shared :reddit_req_options Application env key (see the note in
  # reddit/client_test.exs), so the whole file must run non-concurrently.
  use RedditSavesManager.DataCase, async: false

  alias RedditSavesManager.Saves
  alias RedditSavesManager.Repo

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

  test "tag_post/2 creates the tag if missing and links it" do
    {:ok, post} = Saves.upsert_saved_post(@valid_attrs)
    assert {:ok, _} = Saves.tag_post(post.id, "research")
    assert [%{name: "research"}] = Saves.list_tags_for_post(post.id)
  end

  test "tag_post/2 reuses an existing tag" do
    {:ok, post1} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, post2} = Saves.upsert_saved_post(%{@valid_attrs | reddit_fullname: "t3_def456"})
    {:ok, _} = Saves.tag_post(post1.id, "research")
    {:ok, _} = Saves.tag_post(post2.id, "research")
    assert Repo.aggregate(RedditSavesManager.Saves.Tag, :count) == 1
  end

  test "list_active_posts/1 filters by tag" do
    {:ok, post1} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, _post2} = Saves.upsert_saved_post(%{@valid_attrs | reddit_fullname: "t3_def456"})
    {:ok, _} = Saves.tag_post(post1.id, "research")

    assert [found] = Saves.list_active_posts(%{tag: "research"})
    assert found.id == post1.id
  end

  test "search_posts/1 finds posts by title and body text" do
    {:ok, _} =
      Saves.upsert_saved_post(
        @valid_attrs
        |> Map.put(:title, "GenServer timeout tuning")
        |> Map.put(:selftext, "discussion of :hibernate")
      )

    {:ok, _} =
      Saves.upsert_saved_post(
        @valid_attrs
        |> Map.put(:reddit_fullname, "t3_zzz999")
        |> Map.put(:title, "Photo booth build")
        |> Map.put(:selftext, "DNP printer notes")
      )

    assert [found] = Saves.search_posts("GenServer")
    assert found.title == "GenServer timeout tuning"
  end
end
