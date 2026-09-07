defmodule RedditSavesManager.Repo.Migrations.AddUniqueIndexToResearchDocsSavedPostId do
  use Ecto.Migration

  # Only one research doc per post now (generating overwrites), so
  # saved_post_id must be unique to make generate_and_save/3's upsert work.
  def up do
    drop index(:research_docs, [:saved_post_id])
    create unique_index(:research_docs, [:saved_post_id])
  end

  def down do
    drop index(:research_docs, [:saved_post_id])
    create index(:research_docs, [:saved_post_id])
  end
end
