defmodule RedditSavesManager.Research.OpenRouterClientTest do
  # async: false — stubs Req via the shared :open_router_req_options
  # Application env key (see the note in reddit/client_test.exs; the same
  # global-state hazard applies here).
  use ExUnit.Case, async: false
  alias RedditSavesManager.Research.OpenRouterClient

  setup do
    Application.put_env(:reddit_saves_manager, :open_router_req_options,
      plug: {Req.Test, OpenRouterClient}
    )

    :ok
  end

  test "generate/1 returns the model's markdown content on success" do
    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "# Research Doc\n\nSummary here."}}]
      })
    end)

    assert {:ok, "# Research Doc\n\nSummary here."} = OpenRouterClient.generate("some prompt")
  end

  test "generate/1 returns an error on non-200 response" do
    Req.Test.stub(OpenRouterClient, fn conn ->
      Plug.Conn.send_resp(conn, 500, "{}")
    end)

    assert {:error, _} = OpenRouterClient.generate("some prompt")
  end
end
