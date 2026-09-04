defmodule RedditSavesManager.Repo.Migrations.CreateTagsAndPostTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false
      timestamps()
    end

    create unique_index(:tags, [:name])

    create table(:post_tags) do
      add :saved_post_id, references(:saved_posts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:post_tags, [:saved_post_id, :tag_id])
  end
end
