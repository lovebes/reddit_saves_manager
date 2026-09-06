defmodule RedditSavesManagerWeb.PostsLiveIndexTest do
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

  test "refresh reloads the list from the DB", %{conn: conn, post: post} do
    {:ok, view, _html} = live(conn, ~p"/posts")

    html = view |> element("button", "Refresh list") |> render_click()

    assert html =~ "Refreshed"
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

    html =
      view
      |> form("#tag-form-#{post.id}", tag: %{name: "research"})
      |> render_submit()

    assert html =~ "research"
  end

  test "bulk unsave archives selected posts locally", %{conn: conn, post: post} do
    {:ok, view, _html} = live(conn, ~p"/posts")

    view |> element("input[phx-value-id='#{post.id}']") |> render_click()
    html = view |> element("button", "Unsave selected") |> render_click()

    refute html =~ post.title
  end
end
