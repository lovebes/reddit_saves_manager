defmodule RedditSavesManagerWeb.PageController do
  use RedditSavesManagerWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/posts")
  end

  def guide(conn, _params) do
    render(conn, :guide)
  end
end
