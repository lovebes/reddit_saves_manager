defmodule RedditSavesManagerWeb.PostsLive.Index do
  use RedditSavesManagerWeb, :live_view

  alias RedditSavesManager.Saves
  alias RedditSavesManager.Saves.Sync
  alias RedditSavesManager.Reddit

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, filters: %{}, posts: Saves.list_active_posts(), selected_ids: MapSet.new())}
  end

  def handle_event("filter", %{"filters" => filters}, socket) do
    normalized =
      filters
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)

    {:noreply, assign(socket, filters: normalized, posts: Saves.list_active_posts(normalized))}
  end

  def handle_event("sync", _params, socket) do
    case Reddit.valid_access_token() do
      {:ok, access_token} ->
        # `username` is fetched once via Reddit's /api/v1/me in a follow-up
        # if needed; for now this reads from application config set alongside
        # the OAuth credentials, since it's your own single account.
        username = Application.fetch_env!(:reddit_saves_manager, :reddit)[:username]

        case Sync.run(access_token, username) do
          {:ok, %{synced: count}} ->
            {:noreply,
             socket
             |> put_flash(:info, "Synced #{count} posts")
             |> assign(posts: Saves.list_active_posts(socket.assigns.filters))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Sync failed: #{inspect(reason)}")}
        end

      {:error, :not_authenticated} ->
        {:noreply, put_flash(socket, :error, "Connect your Reddit account first")}
    end
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
end
