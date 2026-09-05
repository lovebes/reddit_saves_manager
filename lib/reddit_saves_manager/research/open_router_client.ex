defmodule RedditSavesManager.Research.OpenRouterClient do
  @endpoint "https://openrouter.ai/api/v1/chat/completions"

  defp config, do: Application.fetch_env!(:reddit_saves_manager, :open_router) |> Map.new()
  defp req_options, do: Application.get_env(:reddit_saves_manager, :open_router_req_options, [])

  def model, do: config()[:model]

  def generate(prompt) do
    %{api_key: api_key, model: model} = config()

    result =
      Req.post(
        [
          url: @endpoint,
          json: %{
            "model" => model,
            "messages" => [%{"role" => "user", "content" => prompt}]
          },
          auth: {:bearer, api_key}
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
