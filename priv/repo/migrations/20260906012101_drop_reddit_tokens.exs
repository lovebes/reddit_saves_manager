defmodule RedditSavesManager.Repo.Migrations.DropRedditTokens do
  use Ecto.Migration

  def up do
    drop table(:reddit_tokens)
  end

  def down do
    create table(:reddit_tokens) do
      add :access_token, :string, null: false
      add :refresh_token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps()
    end
  end
end
