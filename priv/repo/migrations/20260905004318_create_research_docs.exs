defmodule RedditSavesManager.Repo.Migrations.CreateResearchDocs do
  use Ecto.Migration

  def change do
    create table(:research_docs) do
      add :saved_post_id, references(:saved_posts, on_delete: :delete_all), null: false
      add :file_path, :string, null: false
      add :comment_count_used, :integer, null: false
      add :model, :string, null: false
      add :generated_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:research_docs, [:saved_post_id])
  end
end
