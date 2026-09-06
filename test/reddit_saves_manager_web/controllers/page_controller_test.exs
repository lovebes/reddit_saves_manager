defmodule RedditSavesManagerWeb.PageControllerTest do
  use RedditSavesManagerWeb.ConnCase

  test "GET / redirects to the saved posts list", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/posts"
  end
end
