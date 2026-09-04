defmodule RedditSavesManagerWeb.PageController do
  use RedditSavesManagerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
