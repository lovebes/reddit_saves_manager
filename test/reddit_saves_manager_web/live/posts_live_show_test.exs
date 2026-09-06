defmodule RedditSavesManagerWeb.PostsLiveShowTest do
  # async: false — the doc-generation test stubs Req via the shared
  # :open_router_req_options Application env key.
  use RedditSavesManagerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias RedditSavesManager.Saves
  alias RedditSavesManager.Research.OpenRouterClient

  setup do
    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_show1",
        type: "link",
        title: "Show page post",
        subreddit: "elixir",
        permalink: "/r/elixir/comments/show1/show_page_post/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    %{post: post}
  end

  test "renders the post title and body", %{conn: conn, post: post} do
    {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")
    assert html =~ post.title
  end

  test "generating a research doc shows a success flash", %{conn: conn, post: post} do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("reddit_research_show_test_#{System.unique_integer([:positive])}")

    Application.put_env(:reddit_saves_manager, :research_output_dir, tmp_dir)

    Application.put_env(:reddit_saves_manager, :open_router_req_options,
      plug: {Req.Test, OpenRouterClient}
    )

    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "# Doc"}}]})
    end)

    {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

    html =
      view
      |> form("#generate-doc-form",
        doc: %{comment_count: "10", comments_raw: "some raw comments"}
      )
      |> render_submit()

    assert html =~ "Research doc generated"
  end
end
