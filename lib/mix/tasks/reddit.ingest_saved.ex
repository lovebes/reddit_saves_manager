defmodule Mix.Tasks.Reddit.IngestSaved do
  @shortdoc "Upserts saved posts/comments from a browser-scraped JSON file"

  @moduledoc """
  Usage: mix reddit.ingest_saved path/to/saved.json

  Reads a JSON array of saved-post/comment objects (produced by scraping
  reddit.com/user/<you>/saved/ in a browser, since Reddit's API denies
  the "saved" scope to new OAuth apps) and upserts each into saved_posts.

  Expected object shape (extra keys ignored):

      {
        "reddit_fullname": "t3_1w7bfon",
        "type": "link",              // "link" or "comment"
        "title": "...",
        "subreddit": "SideProject",  // no leading r/
        "url": "https://...",        // optional
        "permalink": "/r/SideProject/comments/1w7bfon/.../",
        "author": "someuser",        // optional
        "score": 17,                 // optional, default 0
        "created_utc": "2026-09-04T10:47:28Z",  // optional, ISO8601 or unix seconds
        "selftext": "...",           // optional, post body or comment body, copied verbatim
        "comments_raw": "..."        // optional, raw copied comment-section text (unstructured;
                                      // the research-doc prompt step cleans it up, not this task)
      }
  """

  use Mix.Task

  alias RedditSavesManager.Saves

  @impl Mix.Task
  def run([path]) do
    Mix.Task.run("app.start")

    path
    |> File.read!()
    |> Jason.decode!()
    |> List.wrap()
    |> Enum.each(&ingest_one/1)
  end

  def run(_), do: Mix.raise("Usage: mix reddit.ingest_saved path/to/saved.json")

  defp ingest_one(item) do
    attrs = %{
      reddit_fullname: Map.fetch!(item, "reddit_fullname"),
      type: Map.fetch!(item, "type"),
      title: Map.fetch!(item, "title"),
      subreddit: Map.fetch!(item, "subreddit"),
      permalink: Map.fetch!(item, "permalink"),
      url: item["url"],
      author: item["author"],
      score: item["score"] || 0,
      created_utc: parse_datetime(item["created_utc"]),
      selftext: item["selftext"],
      comments_raw: item["comments_raw"],
      saved_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case Saves.upsert_saved_post(attrs) do
      {:ok, post} ->
        Mix.shell().info("ingested #{post.reddit_fullname} — #{post.title}")

      {:error, changeset} ->
        Mix.shell().error("failed on #{attrs.reddit_fullname}: #{inspect(changeset.errors)}")
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_integer(value) or is_float(value) do
    value |> trunc() |> DateTime.from_unix!() |> DateTime.truncate(:second)
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      {:error, _} -> nil
    end
  end
end
