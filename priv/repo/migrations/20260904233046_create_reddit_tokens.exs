defmodule RedditSavesManager.Repo.Migrations.CreateRedditTokens do
  use Ecto.Migration

  def change do
    create table(:reddit_tokens) do
      add :access_token, :string, null: false
      add :refresh_token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps()
    end
  end
end
