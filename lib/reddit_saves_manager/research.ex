defmodule RedditSavesManager.Research do
  def top_comments(comments, n) do
    comments
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(n)
  end
end
