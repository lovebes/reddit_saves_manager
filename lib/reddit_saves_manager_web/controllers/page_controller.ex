defmodule RedditSavesManagerWeb.PageController do
  use RedditSavesManagerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def guide(conn, _params) do
    render(conn, :guide)
  end
end
