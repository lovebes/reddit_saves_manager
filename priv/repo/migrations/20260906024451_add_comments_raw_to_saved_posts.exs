defmodule RedditSavesManager.Repo.Migrations.AddCommentsRawToSavedPosts do
  use Ecto.Migration

  def change do
    alter table(:saved_posts) do
      add :comments_raw, :text
    end
  end
end
