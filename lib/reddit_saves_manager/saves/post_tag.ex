defmodule RedditSavesManager.Saves.PostTag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_tags" do
    belongs_to :saved_post, RedditSavesManager.Saves.SavedPost
    belongs_to :tag, RedditSavesManager.Saves.Tag
    timestamps()
  end

  def changeset(post_tag, attrs) do
    post_tag
    |> cast(attrs, [:saved_post_id, :tag_id])
    |> validate_required([:saved_post_id, :tag_id])
    |> unique_constraint([:saved_post_id, :tag_id])
  end
end
