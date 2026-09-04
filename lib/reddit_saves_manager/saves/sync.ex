defmodule RedditSavesManager.Saves.Sync do
  alias RedditSavesManager.Reddit.Client
  alias RedditSavesManager.Saves

  def run(access_token, username) do
    case fetch_all(access_token, username, nil, 0) do
      {:error, _reason} = error -> error
      synced when is_integer(synced) -> {:ok, %{synced: synced}}
    end
  end

  defp fetch_all(access_token, username, after_cursor, acc) do
    case Client.fetch_saved(access_token, username, after_cursor) do
      {:ok, %{children: children, after: nil}} ->
        acc + upsert_all(children)

      {:ok, %{children: children, after: next_cursor}} ->
        fetch_all(access_token, username, next_cursor, acc + upsert_all(children))

      {:error, _reason} = error ->
        error
    end
  end

  defp upsert_all(children) do
    Enum.reduce(children, 0, fn data, count ->
      attrs = %{
        reddit_fullname: data["name"],
        type: if(String.starts_with?(data["name"], "t1_"), do: "comment", else: "link"),
        title: data["title"] || data["link_title"] || "(comment)",
        subreddit: data["subreddit"],
        url: data["url"],
        permalink: data["permalink"],
        author: data["author"],
        score: data["score"] || 0,
        created_utc: unix_to_datetime(data["created_utc"]),
        selftext: data["selftext"] || data["body"],
        saved_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case Saves.upsert_saved_post(attrs) do
        {:ok, _} -> count + 1
        {:error, _} -> count
      end
    end)
  end

  defp unix_to_datetime(nil), do: nil

  defp unix_to_datetime(unix) do
    unix |> trunc() |> DateTime.from_unix!() |> DateTime.truncate(:second)
  end
end
