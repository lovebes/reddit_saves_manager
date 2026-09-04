defmodule RedditSavesManager.Reddit do
  alias RedditSavesManager.Repo
  alias RedditSavesManager.Reddit.{Token, Client}

  def get_token do
    Token |> Repo.all() |> List.first()
  end

  def save_token(attrs) do
    case get_token() do
      nil -> %Token{}
      existing -> existing
    end
    |> Token.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def valid_access_token do
    case get_token() do
      nil ->
        {:error, :not_authenticated}

      %Token{expires_at: expires_at} = token ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, token.access_token}
        else
          refresh_and_store(token)
        end
    end
  end

  defp refresh_and_store(%Token{refresh_token: refresh_token}) do
    with {:ok, %{access_token: new_access_token, expires_in: expires_in}} <-
           Client.refresh_token(refresh_token) do
      expires_at =
        DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)

      {:ok, _} =
        save_token(%{
          access_token: new_access_token,
          refresh_token: refresh_token,
          expires_at: expires_at
        })

      {:ok, new_access_token}
    end
  end
end
