defmodule RedditSavesManager.ResearchTest do
  use RedditSavesManager.DataCase, async: false
  alias RedditSavesManager.Research
  alias RedditSavesManager.Saves
  alias RedditSavesManager.Reddit.Client, as: RedditClient
  alias RedditSavesManager.Research.OpenRouterClient

  test "top_comments/2 sorts by score descending and takes n" do
    comments = [
      %{author: "a", score: 5, body: "meh"},
      %{author: "b", score: 42, body: "great point"},
      %{author: "c", score: 10, body: "also good"}
    ]

    assert [%{author: "b"}, %{author: "c"}] = Research.top_comments(comments, 2)
  end

  test "top_comments/2 returns all comments if n exceeds count" do
    comments = [%{author: "a", score: 1, body: "x"}]
    assert [%{author: "a"}] = Research.top_comments(comments, 50)
  end

  test "build_prompt/2 includes post title, url, and comment bodies" do
    post = %Saves.SavedPost{
      title: "OTP kata notes",
      url: "https://reddit.com/x",
      subreddit: "elixir",
      selftext: "some body"
    }

    comments = [%{author: "a", score: 10, body: "great insight"}]

    prompt = RedditSavesManager.Research.build_prompt(post, comments)

    assert prompt =~ "OTP kata notes"
    assert prompt =~ "https://reddit.com/x"
    assert prompt =~ "great insight"
  end

  test "generate_and_save/2 fetches comments, calls OpenRouter, writes a file, and records metadata" do
    tmp_dir =
      System.tmp_dir!() |> Path.join("reddit_research_test_#{System.unique_integer([:positive])}")

    Application.put_env(:reddit_saves_manager, :research_output_dir, tmp_dir)

    Application.put_env(:reddit_saves_manager, :reddit_req_options,
      plug: {Req.Test, RedditClient}
    )

    Application.put_env(:reddit_saves_manager, :open_router_req_options,
      plug: {Req.Test, OpenRouterClient}
    )

    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      RedditSavesManager.Reddit.save_token(%{
        access_token: "atok",
        refresh_token: "rtok",
        expires_at: future
      })

    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_res1",
        type: "link",
        title: "OTP kata notes",
        subreddit: "elixir",
        permalink: "/r/elixir/comments/res1/otp_kata_notes/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    Req.Test.stub(RedditClient, fn conn ->
      Req.Test.json(conn, [
        %{},
        %{
          "data" => %{
            "children" => [
              %{
                "kind" => "t1",
                "data" => %{"author" => "a", "score" => 10, "body" => "great insight"}
              }
            ]
          }
        }
      ])
    end)

    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "# Doc\n\nContent"}}]})
    end)

    assert {:ok, doc} = RedditSavesManager.Research.generate_and_save(post, 5)
    assert doc.comment_count_used == 5
    assert File.exists?(doc.file_path)
    assert File.read!(doc.file_path) =~ "# Doc"
  end
end
