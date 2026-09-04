defmodule RedditSavesManager.Repo do
  use Ecto.Repo,
    otp_app: :reddit_saves_manager,
    adapter: Ecto.Adapters.SQLite3
end
