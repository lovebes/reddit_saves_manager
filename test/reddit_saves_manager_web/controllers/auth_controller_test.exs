defmodule RedditSavesManagerWeb.AuthControllerTest do
  use RedditSavesManagerWeb.ConnCase

  test "GET /auth/reddit/callback with an error param redirects home with a friendly flash", %{
    conn: conn
  } do
    conn = get(conn, ~p"/auth/reddit/callback", %{"error" => "access_denied"})

    assert redirected_to(conn) == ~p"/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Reddit authorization was denied"
  end
end
