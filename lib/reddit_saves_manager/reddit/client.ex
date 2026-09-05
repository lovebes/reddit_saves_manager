defmodule RedditSavesManager.Reddit.Client do
  @authorize_endpoint "https://www.reddit.com/api/v1/authorize"
  @token_endpoint "https://www.reddit.com/api/v1/access_token"
  @api_base "https://oauth.reddit.com"

  # Reddit's API rules require a distinctive User-Agent; generic HTTP-client
  # user agents can be rate-limited or rejected outright.
  @user_agent "reddit-saves-manager/0.1 (personal use script)"

  defp config, do: Application.fetch_env!(:reddit_saves_manager, :reddit) |> Map.new()
  defp req_options, do: Application.get_env(:reddit_saves_manager, :reddit_req_options, [])

  def authorize_url(state) do
    %{client_id: client_id, redirect_uri: redirect_uri} = config()

    query =
      URI.encode_query(%{
        "client_id" => client_id,
        "response_type" => "code",
        "state" => state,
        "redirect_uri" => redirect_uri,
        "duration" => "permanent",
        "scope" => "history save identity"
      })

    @authorize_endpoint <> "?" <> query
  end

  def exchange_code(code) do
    %{client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri} = config()

    body = %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri
    }

    post_token(body, client_id, client_secret)
  end

  def refresh_token(refresh_token) do
    %{client_id: client_id, client_secret: client_secret} = config()
    body = %{"grant_type" => "refresh_token", "refresh_token" => refresh_token}
    post_token(body, client_id, client_secret)
  end

  defp post_token(form_body, client_id, client_secret) do
    result =
      Req.post(
        [
          url: @token_endpoint,
          form: form_body,
          auth: {:basic, "#{client_id}:#{client_secret}"},
          headers: [{"user-agent", @user_agent}]
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"],
           expires_in: body["expires_in"]
         }
         |> Map.reject(fn {_, v} -> is_nil(v) end)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_saved(access_token, username, after_cursor \\ nil) do
    params =
      if after_cursor, do: %{"after" => after_cursor, "limit" => 100}, else: %{"limit" => 100}

    result =
      Req.get(
        [
          url: @api_base <> "/user/#{username}/saved",
          params: params,
          auth: {:bearer, access_token},
          headers: [{"user-agent", @user_agent}]
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: %{"data" => %{"children" => children, "after" => after_cursor}}}} ->
        {:ok, %{children: Enum.map(children, & &1["data"]), after: after_cursor}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_comments(access_token, subreddit, post_id36) do
    result =
      Req.get(
        [
          url: @api_base <> "/r/#{subreddit}/comments/#{post_id36}",
          auth: {:bearer, access_token},
          headers: [{"user-agent", @user_agent}]
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: [_post_listing, %{"data" => %{"children" => children}}]}} ->
        comments =
          children
          |> Enum.filter(&(&1["kind"] == "t1"))
          |> Enum.map(fn %{"data" => d} ->
            %{author: d["author"], score: d["score"] || 0, body: d["body"] || ""}
          end)

        {:ok, comments}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def unsave(access_token, fullname) do
    result =
      Req.post(
        [
          url: @api_base <> "/api/unsave",
          form: %{"id" => fullname},
          auth: {:bearer, access_token},
          headers: [{"user-agent", @user_agent}]
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:unexpected_status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
