defmodule RedditSavesManager.Saves.SavedPost do
  use Ecto.Schema
  import Ecto.Changeset

  schema "saved_posts" do
    field :reddit_fullname, :string
    field :type, :string
    field :title, :string
    field :subreddit, :string
    field :url, :string
    field :permalink, :string
    field :author, :string
    field :score, :integer, default: 0
    field :created_utc, :utc_datetime
    field :selftext, :string
    field :saved_at, :utc_datetime
    field :archived_at, :utc_datetime

    timestamps()
  end

  @required [:reddit_fullname, :type, :title, :subreddit, :permalink, :saved_at]
  @optional [:url, :author, :score, :created_utc, :selftext, :archived_at]

  def changeset(saved_post, attrs) do
    saved_post
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:reddit_fullname)
  end
end
