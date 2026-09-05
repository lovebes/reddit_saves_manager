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

  test "renders a link to connect a Reddit account", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/posts")
    assert html =~ ~s(href="/auth/reddit")
  end

  test "syncing with no Reddit token connected shows a flash message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/posts")

    html = view |> element("button", "Sync now") |> render_click()

    assert html =~ "Connect your Reddit account first"
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

  test "bulk unsave archives selected posts", %{conn: conn, post: post} do
    Application.put_env(:reddit_saves_manager, :reddit_req_options,
      plug: {Req.Test, RedditSavesManager.Reddit.Client}
    )

    Req.Test.stub(RedditSavesManager.Reddit.Client, fn conn ->
      Plug.Conn.send_resp(conn, 200, "{}")
    end)

    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
    {:ok, _} = RedditSavesManager.Reddit.save_token(%{access_token: "atok", refresh_token: "rtok", expires_at: future})

    {:ok, view, _html} = live(conn, ~p"/posts")

    view |> element("input[phx-value-id='#{post.id}']") |> render_click()
    html = view |> element("button", "Unsave selected") |> render_click()

    refute html =~ post.title
  end
end
