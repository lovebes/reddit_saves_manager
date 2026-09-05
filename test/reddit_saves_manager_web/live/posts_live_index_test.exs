defmodule RedditSavesManagerWeb.PostsLiveIndexTest do
  # async: false — the bulk-unsave test added in Task 9 stubs Req via the
  # shared :reddit_req_options Application env key (see the note in
  # reddit/client_test.exs).
  use RedditSavesManagerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias RedditSavesManager.Saves

  setup do
    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_abc",
        type: "link",
        title: "OTP kata notes",
        subreddit: "elixir",
        permalink: "/r/elixir/abc/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    %{post: post}
  end

  test "renders the list of active saved posts", %{conn: conn, post: post} do
    {:ok, _view, html} = live(conn, ~p"/posts")
    assert html =~ post.title
  end

  test "filters by subreddit", %{conn: conn} do
    {:ok, _} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_xyz",
        type: "link",
        title: "Photo booth printer specs",
        subreddit: "photography",
        permalink: "/r/photography/xyz/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/posts")

    html =
      view
      |> form("#filters-form", filters: %{subreddit: "photography"})
      |> render_submit()

    assert html =~ "Photo booth printer specs"
    refute html =~ "OTP kata notes"
  end

  test "search box filters by full-text match", %{conn: conn} do
    {:ok, _} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_search1",
        type: "link",
        title: "Deep dive on Erlang schedulers",
        subreddit: "erlang",
        permalink: "/r/erlang/1/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/posts")

    html =
      view
      |> form("#search-form", search: %{query: "schedulers"})
      |> render_submit()

    assert html =~ "Deep dive on Erlang schedulers"
    refute html =~ "OTP kata notes"
  end

  test "tagging a post from the list", %{conn: conn, post: post} do
    {:ok, view, _html} = live(conn, ~p"/posts")

    view
    |> form("#tag-form-#{post.id}", tag: %{name: "research"})
    |> render_submit()

    # Fresh mount with new DB connection to verify tag persisted
    {:ok, _view2, html} = live(conn, ~p"/posts")
    assert html =~ "research"
  end
end
