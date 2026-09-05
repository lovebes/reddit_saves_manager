defmodule RedditSavesManager.ResearchTest do
  use ExUnit.Case, async: true
  alias RedditSavesManager.Research
  # Note for Task 11: this module is upgraded to `use RedditSavesManager.DataCase,
  # async: false` there (generate_and_save/2 touches the DB and stubs Req via
  # shared Application env keys — see the note in reddit/client_test.exs).

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
end
