defmodule RedditSavesManager.ResearchTest do
  use RedditSavesManager.DataCase, async: false
  alias RedditSavesManager.Research
  alias RedditSavesManager.Saves
  alias RedditSavesManager.Research.OpenRouterClient

  test "build_prompt/3 includes post title, url, raw comments, and the top-N instruction" do
    post = %Saves.SavedPost{
      title: "OTP kata notes",
      url: "https://reddit.com/x",
      subreddit: "elixir",
      selftext: "some body"
    }

    prompt = Research.build_prompt(post, "raw jumbled comment text, score 42", 5)

    assert prompt =~ "OTP kata notes"
    assert prompt =~ "https://reddit.com/x"
    assert prompt =~ "raw jumbled comment text, score 42"
    assert prompt =~ "top 5"
  end

  test "generate_and_save/3 sends the raw comments blob to OpenRouter, writes a file, and records metadata" do
    tmp_dir =
      System.tmp_dir!() |> Path.join("reddit_research_test_#{System.unique_integer([:positive])}")

    Application.put_env(:reddit_saves_manager, :research_output_dir, tmp_dir)

    Application.put_env(:reddit_saves_manager, :open_router_req_options,
      plug: {Req.Test, OpenRouterClient}
    )

    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_res1",
        type: "link",
        title: "OTP kata notes",
        subreddit: "elixir",
        permalink: "/r/elixir/comments/res1/otp_kata_notes/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "# Doc\n\nContent"}}]})
    end)

    assert {:ok, doc} = Research.generate_and_save(post, "author a, 10 points: great insight", 5)
    assert doc.comment_count_used == 5
    assert File.exists?(doc.file_path)
    assert File.read!(doc.file_path) =~ "# Doc"
  end

  test "generate_and_save/3 produces a valid, non-colliding file path for a title with no ASCII alphanumeric characters" do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("reddit_research_test_#{System.unique_integer([:positive])}")

    Application.put_env(:reddit_saves_manager, :research_output_dir, tmp_dir)

    Application.put_env(:reddit_saves_manager, :open_router_req_options,
      plug: {Req.Test, OpenRouterClient}
    )

    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_kor1",
        type: "link",
        title: "한글 제목",
        subreddit: "korea",
        permalink: "/r/korea/comments/kor1/korean_title/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "# Doc"}}]})
    end)

    assert {:ok, doc} = Research.generate_and_save(post, "", 5)
    assert File.exists?(doc.file_path)
    filename = Path.basename(doc.file_path)
    refute String.starts_with?(filename, ".")
    assert filename == "post-#{post.id}.md"
  end
end
