defmodule RedditSavesManagerWeb.PostsLive.Index do
  use RedditSavesManagerWeb, :live_view

  alias RedditSavesManager.Saves

  def mount(_params, _session, socket) do
    posts = Saves.list_active_posts()

    {:ok,
     assign(socket,
       filters: %{},
       posts: posts,
       selected_ids: MapSet.new(),
       tags_by_post_id: tags_by_post_id(posts)
     )}
  end

  defp tags_by_post_id(posts) do
    Map.new(posts, fn post -> {post.id, Saves.list_tags_for_post(post.id)} end)
  end

  def handle_event("filter", %{"filters" => filters}, socket) do
    normalized =
      filters
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    posts = Saves.list_active_posts(normalized)

    {:noreply,
     assign(socket,
       filters: normalized,
       posts: posts,
       tags_by_post_id: tags_by_post_id(posts)
     )}
  end

  # Reloads the list from the DB. Syncing itself happens out-of-band via
  # `mix reddit.ingest_saved` (Reddit denies the OAuth scopes an in-app
  # sync would need) — this just picks up whatever that ingest wrote.
  def handle_event("refresh", _params, socket) do
    posts = Saves.list_active_posts(socket.assigns.filters)

    {:noreply,
     socket
     |> put_flash(:info, "Refreshed")
     |> assign(posts: posts, tags_by_post_id: tags_by_post_id(posts))}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected_ids =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, selected_ids: selected_ids)}
  end

  def handle_event("search", %{"search" => %{"query" => ""}}, socket) do
    posts = Saves.list_active_posts(socket.assigns.filters)

    {:noreply, assign(socket, posts: posts, tags_by_post_id: tags_by_post_id(posts))}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    posts = Saves.search_posts(query)

    {:noreply, assign(socket, posts: posts, tags_by_post_id: tags_by_post_id(posts))}
  end

  def handle_event("add_tag", %{"post_id" => _post_id, "tag" => %{"name" => ""}}, socket) do
    {:noreply, socket}
  end

  def handle_event("add_tag", %{"post_id" => post_id, "tag" => %{"name" => name}}, socket) do
    post_id = String.to_integer(post_id)
    {:ok, _} = Saves.tag_post(post_id, name)

    {:noreply,
     assign(socket,
       tags_by_post_id:
         Map.put(
           socket.assigns.tags_by_post_id,
           post_id,
           Saves.list_tags_for_post(post_id)
         )
     )}
  end

  # Archives the selection locally only — it doesn't touch reddit.com. Actually
  # removing a post from Reddit's own saved list is a separate action to ask
  # for when you want it (Reddit denies the OAuth scope an in-app call
  # would need, so it's done by driving a browser instead).
  def handle_event("bulk_unsave", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)
    {:ok, count} = Saves.archive_posts(ids)

    {:noreply,
     socket
     |> put_flash(:info, "Archived #{count} posts locally")
     |> assign(posts: Saves.list_active_posts(socket.assigns.filters), selected_ids: MapSet.new())}
  end
end
