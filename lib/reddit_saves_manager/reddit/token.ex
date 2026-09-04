defmodule RedditSavesManager.Reddit.Token do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reddit_tokens" do
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:access_token, :refresh_token, :expires_at])
    |> validate_required([:access_token, :refresh_token, :expires_at])
  end
end
