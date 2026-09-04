defmodule RedditSavesManager.Saves.SyncTest do
  # async: false — stubs Req via the shared :reddit_req_options Application
  # env key (see the note in reddit/client_test.exs).
  use RedditSavesManager.DataCase, async: false
  alias RedditSavesManager.Saves
  alias RedditSavesManager.Saves.Sync
  alias RedditSavesManager.Reddit.Client

  setup do
    Application.put_env(:reddit_saves_manager, :reddit_req_options, plug: {Req.Test, Client})
    :ok
  end

  test "run/2 paginates through all saved posts and upserts them" do
    Req.Test.stub(Client, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.params["after"] do
        nil ->
          Req.Test.json(conn, %{
            "data" => %{
              "after" => "t3_page2",
              "children" => [
                %{"data" => %{"name" => "t3_a", "title" => "Post A", "subreddit" => "elixir", "permalink" => "/r/elixir/a/", "saved" => true, "created_utc" => 1_700_000_000}}
              ]
            }
          })

        "t3_page2" ->
          Req.Test.json(conn, %{
            "data" => %{
              "after" => nil,
              "children" => [
                %{"data" => %{"name" => "t3_b", "title" => "Post B", "subreddit" => "elixir", "permalink" => "/r/elixir/b/", "saved" => true, "created_utc" => 1_700_000_100}}
              ]
            }
          })
      end
    end)

    assert {:ok, %{synced: 2}} = Sync.run("atok", "sjkim")
    assert length(Saves.list_active_posts()) == 2
  end

  test "run/2 returns error when Reddit API fails" do
    Req.Test.stub(Client, fn conn ->
      # Simulate a non-200 status (e.g., 401 Unauthorized)
      conn
      |> Plug.Conn.send_resp(401, "{\"error\": \"Unauthorized\"}")
    end)

    result = Sync.run("invalid_token", "sjkim")
    assert {:error, _reason} = result
    # Ensure we didn't create partial records
    assert length(Saves.list_active_posts()) == 0
  end
end
