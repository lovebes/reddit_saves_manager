defmodule RedditSavesManagerWeb.ResearchDocController do
  use RedditSavesManagerWeb, :controller

  alias RedditSavesManager.Research

  def show(conn, %{"post_id" => post_id}) do
    with %Research.Doc{} = doc <- Research.latest_doc(String.to_integer(post_id)),
         content when is_binary(content) <- Research.read_doc_content(doc) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, content)
    else
      _ -> send_resp(conn, 404, "No research doc found for this post")
    end
  end
end
