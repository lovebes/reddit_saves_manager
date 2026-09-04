defmodule RedditSavesManager.Repo.Migrations.CreateSavedPosts do
  use Ecto.Migration

  def change do
    create table(:saved_posts) do
      add :reddit_fullname, :string, null: false
      add :type, :string, null: false
      add :title, :string, null: false
      add :subreddit, :string, null: false
      add :url, :string
      add :permalink, :string, null: false
      add :author, :string
      add :score, :integer, default: 0
      add :created_utc, :utc_datetime
      add :selftext, :text
      add :saved_at, :utc_datetime, null: false
      add :archived_at, :utc_datetime

      timestamps()
    end

    create unique_index(:saved_posts, [:reddit_fullname])
  end
end
