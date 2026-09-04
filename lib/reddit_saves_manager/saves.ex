defmodule RedditSavesManager.Saves do
  import Ecto.Query
  alias RedditSavesManager.Repo
  alias RedditSavesManager.Saves.SavedPost

  def upsert_saved_post(attrs) do
    %SavedPost{}
    |> SavedPost.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :reddit_fullname,
      returning: true
    )
  end

  def list_active_posts do
    SavedPost
    |> where([p], is_nil(p.archived_at))
    |> order_by([p], desc: p.saved_at)
    |> Repo.all()
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
end
