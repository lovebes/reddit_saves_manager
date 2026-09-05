defmodule RedditSavesManagerWeb.AuthController do
  use RedditSavesManagerWeb, :controller
  alias RedditSavesManager.Reddit
  alias RedditSavesManager.Reddit.Client

  def new(conn, _params) do
    state = Base.encode16(:crypto.strong_rand_bytes(8))

    conn
    |> put_session(:reddit_oauth_state, state)
    |> redirect(external: Client.authorize_url(state))
  end

  def callback(conn, %{"error" => reason}) do
    conn
    |> put_flash(:error, "Reddit authorization was denied (#{reason})")
    |> redirect(to: ~p"/")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    if get_session(conn, :reddit_oauth_state) == state do
      case Client.exchange_code(code) do
        {:ok, %{access_token: access_token, refresh_token: refresh_token, expires_in: expires_in}} ->
          expires_at =
            DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)

          {:ok, _} =
            Reddit.save_token(%{
              access_token: access_token,
              refresh_token: refresh_token,
              expires_at: expires_at
            })

          conn
          |> put_flash(:info, "Connected to Reddit")
          |> redirect(to: ~p"/posts")

        {:error, reason} ->
          conn
          |> put_flash(:error, "Reddit auth failed: #{inspect(reason)}")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "OAuth state mismatch")
      |> redirect(to: ~p"/")
    end
  end
end
