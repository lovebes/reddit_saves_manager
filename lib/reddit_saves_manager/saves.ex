defmodule RedditSavesManager.Saves do
  import Ecto.Query
  alias RedditSavesManager.Repo
  alias RedditSavesManager.Saves.SavedPost
  alias RedditSavesManager.Saves.{Tag, PostTag}
  alias RedditSavesManager.Reddit.Client

  def upsert_saved_post(attrs) do
    %SavedPost{}
    |> SavedPost.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :reddit_fullname,
      returning: true
    )
  end

  def list_active_posts(filters \\ %{}) do
    SavedPost
    |> where([p], is_nil(p.archived_at))
    |> maybe_filter_subreddit(filters[:subreddit])
    |> maybe_filter_type(filters[:type])
    |> maybe_filter_tag(filters[:tag])
    |> order_by([p], desc: p.saved_at)
    |> Repo.all()
  end

  defp maybe_filter_subreddit(query, nil), do: query
  defp maybe_filter_subreddit(query, subreddit), do: where(query, [p], p.subreddit == ^subreddit)

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, type), do: where(query, [p], p.type == ^type)

  defp maybe_filter_tag(query, nil), do: query

  defp maybe_filter_tag(query, tag_name) do
    query
    |> join(:inner, [p], pt in PostTag, on: pt.saved_post_id == p.id)
    |> join(:inner, [p, pt], t in Tag, on: t.id == pt.tag_id)
    |> where([p, pt, t], t.name == ^tag_name)
  end

  def get_saved_post!(id), do: Repo.get!(SavedPost, id)

  def archive_posts(ids) when is_list(ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      SavedPost
      |> where([p], p.id in ^ids)
      |> Repo.update_all(set: [archived_at: now])

    {:ok, count}
  end

  def tag_post(saved_post_id, tag_name) do
    tag =
      case Repo.get_by(Tag, name: tag_name) do
        nil -> Repo.insert!(Tag.changeset(%Tag{}, %{name: tag_name}))
        existing -> existing
      end

    %PostTag{}
    |> PostTag.changeset(%{saved_post_id: saved_post_id, tag_id: tag.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:saved_post_id, :tag_id])
  end

  def untag_post(saved_post_id, tag_name) do
    with %Tag{} = tag <- Repo.get_by(Tag, name: tag_name) do
      PostTag
      |> where([pt], pt.saved_post_id == ^saved_post_id and pt.tag_id == ^tag.id)
      |> Repo.delete_all()

      :ok
    else
      nil -> :ok
    end
  end

  def list_tags_for_post(saved_post_id) do
    Tag
    |> join(:inner, [t], pt in PostTag, on: pt.tag_id == t.id)
    |> where([t, pt], pt.saved_post_id == ^saved_post_id)
    |> Repo.all()
  end

  def search_posts(query_text) when is_binary(query_text) and query_text != "" do
    sql = """
    SELECT saved_posts.* FROM saved_posts
    JOIN saved_posts_fts ON saved_posts_fts.rowid = saved_posts.id
    WHERE saved_posts_fts MATCH ? AND saved_posts.archived_at IS NULL
    ORDER BY rank
    """

    {:ok, %{rows: rows, columns: columns}} = Repo.query(sql, [query_text])

    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
      |> then(&Repo.load(SavedPost, &1))
    end)
  end

  def search_posts(_), do: []

  def unsave_posts(access_token, ids) when is_list(ids) do
    posts = Enum.map(ids, &get_saved_post!/1)

    {succeeded, failed} =
      Enum.split_with(posts, fn post ->
        Client.unsave(access_token, post.reddit_fullname) == :ok
      end)

    succeeded_ids = Enum.map(succeeded, & &1.id)
    failed_ids = Enum.map(failed, & &1.id)

    if succeeded_ids != [], do: archive_posts(succeeded_ids)

    {:ok, %{unsaved: succeeded_ids, failed: failed_ids}}
  end
end
