defmodule RedditSavesManagerWeb.PostsLive.Show do
  use RedditSavesManagerWeb, :live_view

  alias RedditSavesManager.Saves
  alias RedditSavesManager.Research

  def mount(%{"id" => id}, _session, socket) do
    post = Saves.get_saved_post!(id)
    {:ok, assign(socket, post: post)}
  end

  def handle_event(
        "generate_doc",
        %{"doc" => %{"comment_count" => comment_count, "comments_raw" => comments_raw}},
        socket
      ) do
    comment_count = String.to_integer(comment_count)

    case Research.generate_and_save(socket.assigns.post, comments_raw, comment_count) do
      {:ok, doc} ->
        {:noreply, put_flash(socket, :info, "Research doc generated: #{doc.file_path}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Doc generation failed: #{inspect(reason)}")}
    end
  end
end
