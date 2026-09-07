defmodule RedditSavesManagerWeb.PostsLive.Show do
  use RedditSavesManagerWeb, :live_view

  alias RedditSavesManager.Saves
  alias RedditSavesManager.Research

  def mount(%{"id" => id}, _session, socket) do
    post = Saves.get_saved_post!(id)
    doc = Research.latest_doc(post.id)
    doc_html = doc && doc |> Research.read_doc_content() |> Research.to_html()
    {:ok, assign(socket, post: post, doc: doc, doc_html: doc_html)}
  end

  def handle_event(
        "generate_doc",
        %{"doc" => %{"comment_count" => comment_count, "comments_raw" => comments_raw}},
        socket
      ) do
    comment_count = String.to_integer(comment_count)

    case Research.generate_and_save(socket.assigns.post, comments_raw, comment_count) do
      {:ok, doc} ->
        doc_html = doc |> Research.read_doc_content() |> Research.to_html()

        {:noreply,
         socket
         |> put_flash(:info, "Research doc generated: #{doc.file_path}")
         |> assign(doc: doc, doc_html: doc_html)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Doc generation failed: #{inspect(reason)}")}
    end
  end
end
