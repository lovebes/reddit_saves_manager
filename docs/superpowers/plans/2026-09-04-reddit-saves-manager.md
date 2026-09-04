# Reddit Saves Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-only Phoenix LiveView app that syncs SJ's Reddit saved posts, lets him organize/tag/search/bulk-unsave them, and generates on-demand AI research documents (markdown) from a post plus its top comments via OpenRouter.

**Architecture:** A single Phoenix app with three contexts — `Reddit` (OAuth token lifecycle + Reddit API client), `Saves` (saved posts, tags, search — the organize/declutter data layer), and `Research` (OpenRouter client + markdown doc generation). One SQLite DB. Two LiveViews: an index (list/filter/search/tag/bulk-unsave/sync) and a show page (per-post research doc generation).

**Tech Stack:** Elixir, Phoenix 1.7+ LiveView, SQLite via `ecto_sqlite3`, `Req` for HTTP (Reddit + OpenRouter), `Req.Test` for HTTP mocking in tests, `Dotenvy` for `.env` loading into `config/runtime.exs`.

**Spec:** `docs/superpowers/specs/2026-09-04-reddit-saves-manager-design.md`

## Global Constraints

- Single user, local-only. No deployment, no multi-tenant auth.
- Secrets (`REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET`, `OPENROUTER_API_KEY`, `OPENROUTER_MODEL`) load from `.env` via Dotenvy into `System` env, read in `config/runtime.exs` via `System.fetch_env!/1`. Never logged.
- Reddit OAuth2 "installed app" type, authorization-code flow, redirect `http://localhost:PORT/auth/reddit/callback`.
- Reddit access/refresh tokens are stored in the local SQLite DB (acceptable for a single-user local tool per spec).
- No fixed/enforced default for "number of comments" fed into research-doc generation — always a user-selected value per generation.
- Research docs are written to `~/reddit-research/<slug>.md` with YAML frontmatter (`title`, `url`, `subreddit`, `date`, `tags`). The DB only stores generation metadata, never doc content.
- No background/scheduled sync. Sync is manually triggered only.

---

## File Structure

```
lib/reddit_saves_manager/
  reddit/
    client.ex          # Raw Reddit HTTP calls (authorize_url, exchange_code, refresh_token, fetch_saved, fetch_comments, unsave)
    token.ex           # Ecto schema for the single stored OAuth token row
  reddit.ex            # Reddit context: get/save token, valid_access_token/0 (auto-refresh)
  saves/
    saved_post.ex      # Ecto schema
    tag.ex             # Ecto schema
    post_tag.ex         # Ecto schema (join)
    sync.ex            # Paginate Reddit.Client.fetch_saved/upsert into saved_posts
  saves.ex             # Saves context: CRUD, filters, FTS search, tagging, archive/unsave
  research/
    open_router_client.ex  # Raw OpenRouter HTTP call
    doc.ex                  # Ecto schema for research_docs metadata
  research.ex          # Research context: build_prompt/2, generate_and_save/2

lib/reddit_saves_manager_web/
  controllers/
    auth_controller.ex  # /auth/reddit (redirect) and /auth/reddit/callback
  live/
    posts_live/
      index.ex           # List/filter/search/tag/bulk-unsave/sync LiveView
      index.html.heex
      show.ex            # Post detail + generate-doc LiveView
      show.html.heex
  router.ex              # (modified) add auth + live routes

priv/repo/migrations/
  ..._create_reddit_tokens.exs
  ..._create_saved_posts.exs
  ..._create_tags_and_post_tags.exs
  ..._create_research_docs.exs
  ..._create_saved_posts_fts.exs   # raw SQL: FTS5 virtual table + sync triggers

config/runtime.exs   # (modified) Dotenvy load + Reddit/OpenRouter env config
```

---

### Task 1: Project scaffold, SQLite, and `.env` config

**Files:**
- Create: entire Phoenix app skeleton via generator (see Step 1)
- Modify: `config/runtime.exs`
- Modify: `mix.exs` (add `dotenvy`, `req` deps)
- Create: `.env.example`
- Create: `.gitignore` entry for `.env`

**Interfaces:**
- Produces: a booting Phoenix app (`mix phx.server` works), SQLite repo configured, and three env vars readable anywhere via `Application.fetch_env!(:reddit_saves_manager, :reddit)` / `:open_router`.

- [ ] **Step 1: Generate the Phoenix app into the current directory**

Run from `/home/sj/Documents/projects/reddit_saves_manager` (the `docs/` folder already there is left untouched):

```bash
mix phx.new . --app reddit_saves_manager --module RedditSavesManager --database sqlite3 --no-mailer
```

Answer `Y` to fetch and install dependencies when prompted.

- [ ] **Step 2: Verify the app boots**

Run: `mix phx.server`
Expected: server starts on `http://localhost:4000`, default Phoenix welcome page loads. Stop the server (Ctrl+C twice).

- [ ] **Step 3: Add `dotenvy` and `req` dependencies**

In `mix.exs`, add to `deps/0`:

```elixir
{:dotenvy, "~> 0.8"},
{:req, "~> 0.5"}
```

Run: `mix deps.get`

- [ ] **Step 4: Create `.env.example` and add `.env` to `.gitignore`**

Create `.env.example`:

```
REDDIT_CLIENT_ID=
REDDIT_CLIENT_SECRET=
OPENROUTER_API_KEY=
OPENROUTER_MODEL=anthropic/claude-3.5-sonnet
```

Add a line `.env` to `.gitignore` (append if the file exists from the generator, which it will).

Create your real `.env` by copying `.env.example` and filling in actual values (you'll need to register a Reddit "installed app" at https://www.reddit.com/prefs/apps with redirect URI `http://localhost:4000/auth/reddit/callback`, and an OpenRouter API key from https://openrouter.ai/keys).

- [ ] **Step 5: Wire Dotenvy + env config into `config/runtime.exs`**

Add near the top of `config/runtime.exs` (before the existing `if config_env() == :prod do` block, so it applies in dev too):

```elixir
import Config
import Dotenvy

Dotenvy.source!([Path.absname(".env"), System.get_env()])

config :reddit_saves_manager, :reddit,
  client_id: env!("REDDIT_CLIENT_ID", :string),
  client_secret: env!("REDDIT_CLIENT_SECRET", :string),
  redirect_uri: "http://localhost:4000/auth/reddit/callback"

config :reddit_saves_manager, :open_router,
  api_key: env!("OPENROUTER_API_KEY", :string),
  model: env!("OPENROUTER_MODEL", :string)
```

Note: `config/runtime.exs` already starts with `import Config`; don't duplicate it — just add the `import Dotenvy` line and the block below the existing `import Config`.

- [ ] **Step 6: Verify config loads**

Run: `mix run -e 'IO.inspect(Application.fetch_env!(:reddit_saves_manager, :reddit))'`
Expected: prints your client_id/client_secret/redirect_uri (not crashing on missing `.env` values).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Scaffold Phoenix app with SQLite and .env config"
```

---

### Task 2: `saved_posts` schema, migration, and base `Saves` context

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_saved_posts.exs`
- Create: `lib/reddit_saves_manager/saves/saved_post.ex`
- Create: `lib/reddit_saves_manager/saves.ex`
- Test: `test/reddit_saves_manager/saves_test.exs`

**Interfaces:**
- Produces: `RedditSavesManager.Saves.SavedPost` schema; `RedditSavesManager.Saves.upsert_saved_post/1`, `list_active_posts/0`, `get_saved_post!/1`, `archive_posts/1`.

- [ ] **Step 1: Write the migration**

```elixir
defmodule RedditSavesManager.Repo.Migrations.CreateSavedPosts do
  use Ecto.Migration

  def change do
    create table(:saved_posts) do
      add :reddit_fullname, :string, null: false
      add :type, :string, null: false
      add :title, :string, null: false
      add :subreddit, :string, null: false
      add :url, :string
      add :permalink, :string, null: false
      add :author, :string
      add :score, :integer, default: 0
      add :created_utc, :utc_datetime
      add :selftext, :text
      add :saved_at, :utc_datetime, null: false
      add :archived_at, :utc_datetime

      timestamps()
    end

    create unique_index(:saved_posts, [:reddit_fullname])
  end
end
```

Run: `mix ecto.gen.migration create_saved_posts` first to get the timestamped filename, then paste the body above in place of the generated stub.

- [ ] **Step 2: Write the schema**

```elixir
defmodule RedditSavesManager.Saves.SavedPost do
  use Ecto.Schema
  import Ecto.Changeset

  schema "saved_posts" do
    field :reddit_fullname, :string
    field :type, :string
    field :title, :string
    field :subreddit, :string
    field :url, :string
    field :permalink, :string
    field :author, :string
    field :score, :integer, default: 0
    field :created_utc, :utc_datetime
    field :selftext, :string
    field :saved_at, :utc_datetime
    field :archived_at, :utc_datetime

    timestamps()
  end

  @required [:reddit_fullname, :type, :title, :subreddit, :permalink, :saved_at]
  @optional [:url, :author, :score, :created_utc, :selftext, :archived_at]

  def changeset(saved_post, attrs) do
    saved_post
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:reddit_fullname)
  end
end
```

- [ ] **Step 3: Write the failing test for `upsert_saved_post/1` and `list_active_posts/0`**

```elixir
defmodule RedditSavesManager.SavesTest do
  # async: false — Task 9 appends a test to this file that stubs Req via the
  # shared :reddit_req_options Application env key (see the note in
  # reddit/client_test.exs), so the whole file must run non-concurrently.
  use RedditSavesManager.DataCase, async: false

  alias RedditSavesManager.Saves

  @valid_attrs %{
    reddit_fullname: "t3_abc123",
    type: "link",
    title: "Some post",
    subreddit: "elixir",
    permalink: "/r/elixir/comments/abc123/some_post/",
    saved_at: ~U[2026-01-01 00:00:00Z]
  }

  test "upsert_saved_post/1 inserts a new post" do
    assert {:ok, post} = Saves.upsert_saved_post(@valid_attrs)
    assert post.reddit_fullname == "t3_abc123"
  end

  test "upsert_saved_post/1 updates on duplicate reddit_fullname" do
    {:ok, _} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, updated} = Saves.upsert_saved_post(Map.put(@valid_attrs, :score, 42))
    assert updated.score == 42
    assert Saves.list_active_posts() |> length() == 1
  end

  test "list_active_posts/0 excludes archived posts" do
    {:ok, post} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, _} = Saves.archive_posts([post.id])
    assert Saves.list_active_posts() == []
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: FAIL — `Saves` module/functions undefined.

- [ ] **Step 5: Write the `Saves` context**

```elixir
defmodule RedditSavesManager.Saves do
  import Ecto.Query
  alias RedditSavesManager.Repo
  alias RedditSavesManager.Saves.SavedPost

  def upsert_saved_post(attrs) do
    %SavedPost{}
    |> SavedPost.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :reddit_fullname,
      returning: true
    )
  end

  def list_active_posts do
    SavedPost
    |> where([p], is_nil(p.archived_at))
    |> order_by([p], desc: p.saved_at)
    |> Repo.all()
  end

  def get_saved_post!(id), do: Repo.get!(SavedPost, id)

  def archive_posts(ids) when is_list(ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      SavedPost
      |> where([p], p.id in ^ids)
      |> Repo.update_all(set: [archived_at: now])

    {:ok, count}
  end
end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: PASS (3 tests)

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations lib/reddit_saves_manager/saves.ex lib/reddit_saves_manager/saves/saved_post.ex test/reddit_saves_manager/saves_test.exs
git commit -m "Add saved_posts schema and base Saves context"
```

---

### Task 3: Tags, `post_tags`, and tagging functions

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_tags_and_post_tags.exs`
- Create: `lib/reddit_saves_manager/saves/tag.ex`
- Create: `lib/reddit_saves_manager/saves/post_tag.ex`
- Modify: `lib/reddit_saves_manager/saves.ex`
- Test: `test/reddit_saves_manager/saves_test.exs`

**Interfaces:**
- Consumes: `Saves.SavedPost` (Task 2)
- Produces: `Saves.tag_post/2` (post_id, tag_name), `Saves.untag_post/2`, `Saves.list_tags_for_post/1`, `Saves.list_active_posts/1` (now accepts a filters map: `%{subreddit: ..., type: ..., tag: ...}`)

- [ ] **Step 1: Write the migration**

```elixir
defmodule RedditSavesManager.Repo.Migrations.CreateTagsAndPostTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false
      timestamps()
    end

    create unique_index(:tags, [:name])

    create table(:post_tags) do
      add :saved_post_id, references(:saved_posts, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:post_tags, [:saved_post_id, :tag_id])
  end
end
```

Run `mix ecto.gen.migration create_tags_and_post_tags` for the filename, paste body in.

- [ ] **Step 2: Write the schemas**

`lib/reddit_saves_manager/saves/tag.ex`:

```elixir
defmodule RedditSavesManager.Saves.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    timestamps()
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
```

`lib/reddit_saves_manager/saves/post_tag.ex`:

```elixir
defmodule RedditSavesManager.Saves.PostTag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_tags" do
    belongs_to :saved_post, RedditSavesManager.Saves.SavedPost
    belongs_to :tag, RedditSavesManager.Saves.Tag
    timestamps()
  end

  def changeset(post_tag, attrs) do
    post_tag
    |> cast(attrs, [:saved_post_id, :tag_id])
    |> validate_required([:saved_post_id, :tag_id])
    |> unique_constraint([:saved_post_id, :tag_id])
  end
end
```

- [ ] **Step 3: Write failing tests for tagging and filtering**

Append to `test/reddit_saves_manager/saves_test.exs`:

```elixir
  test "tag_post/2 creates the tag if missing and links it" do
    {:ok, post} = Saves.upsert_saved_post(@valid_attrs)
    assert {:ok, _} = Saves.tag_post(post.id, "research")
    assert [%{name: "research"}] = Saves.list_tags_for_post(post.id)
  end

  test "tag_post/2 reuses an existing tag" do
    {:ok, post1} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, post2} = Saves.upsert_saved_post(%{@valid_attrs | reddit_fullname: "t3_def456"})
    {:ok, _} = Saves.tag_post(post1.id, "research")
    {:ok, _} = Saves.tag_post(post2.id, "research")
    assert Repo.aggregate(RedditSavesManager.Saves.Tag, :count) == 1
  end

  test "list_active_posts/1 filters by tag" do
    {:ok, post1} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, _post2} = Saves.upsert_saved_post(%{@valid_attrs | reddit_fullname: "t3_def456"})
    {:ok, _} = Saves.tag_post(post1.id, "research")

    assert [found] = Saves.list_active_posts(%{tag: "research"})
    assert found.id == post1.id
  end
```

Add `alias RedditSavesManager.Repo` near the top of the test module if not already present.

- [ ] **Step 4: Run tests to verify they fail**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: FAIL — `tag_post/2`, `list_tags_for_post/1` undefined; `list_active_posts/1` arity mismatch.

- [ ] **Step 5: Implement tagging and filtering in `Saves`**

Add to `lib/reddit_saves_manager/saves.ex` (replace the existing `list_active_posts/0` with the filtered version, keep everything else):

```elixir
  alias RedditSavesManager.Saves.{Tag, PostTag}

  def list_active_posts(filters \\ %{}) do
    SavedPost
    |> where([p], is_nil(p.archived_at))
    |> maybe_filter_subreddit(filters[:subreddit])
    |> maybe_filter_type(filters[:type])
    |> maybe_filter_tag(filters[:tag])
    |> order_by([p], desc: p.saved_at)
    |> Repo.all()
  end

  defp maybe_filter_subreddit(query, nil), do: query
  defp maybe_filter_subreddit(query, subreddit), do: where(query, [p], p.subreddit == ^subreddit)

  defp maybe_filter_type(query, nil), do: query
  defp maybe_filter_type(query, type), do: where(query, [p], p.type == ^type)

  defp maybe_filter_tag(query, nil), do: query

  defp maybe_filter_tag(query, tag_name) do
    query
    |> join(:inner, [p], pt in PostTag, on: pt.saved_post_id == p.id)
    |> join(:inner, [p, pt], t in Tag, on: t.id == pt.tag_id)
    |> where([p, pt, t], t.name == ^tag_name)
  end

  def tag_post(saved_post_id, tag_name) do
    tag =
      case Repo.get_by(Tag, name: tag_name) do
        nil -> Repo.insert!(Tag.changeset(%Tag{}, %{name: tag_name}))
        existing -> existing
      end

    %PostTag{}
    |> PostTag.changeset(%{saved_post_id: saved_post_id, tag_id: tag.id})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:saved_post_id, :tag_id])
  end

  def untag_post(saved_post_id, tag_name) do
    with %Tag{} = tag <- Repo.get_by(Tag, name: tag_name) do
      PostTag
      |> where([pt], pt.saved_post_id == ^saved_post_id and pt.tag_id == ^tag.id)
      |> Repo.delete_all()

      :ok
    else
      nil -> :ok
    end
  end

  def list_tags_for_post(saved_post_id) do
    Tag
    |> join(:inner, [t], pt in PostTag, on: pt.tag_id == t.id)
    |> where([t, pt], pt.saved_post_id == ^saved_post_id)
    |> Repo.all()
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: PASS (6 tests)

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations lib/reddit_saves_manager/saves.ex lib/reddit_saves_manager/saves/tag.ex lib/reddit_saves_manager/saves/post_tag.ex test/reddit_saves_manager/saves_test.exs
git commit -m "Add tagging and post filtering to Saves context"
```

---

### Task 4: Full-text search (FTS5)

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_saved_posts_fts.exs`
- Modify: `lib/reddit_saves_manager/saves.ex`
- Test: `test/reddit_saves_manager/saves_test.exs`

**Interfaces:**
- Consumes: `saved_posts` table (Task 2)
- Produces: `Saves.search_posts/1` (query string) -> list of `SavedPost` ordered by relevance

- [ ] **Step 1: Write the raw-SQL migration for the FTS5 virtual table + sync triggers**

```elixir
defmodule RedditSavesManager.Repo.Migrations.CreateSavedPostsFts do
  use Ecto.Migration

  def up do
    execute """
    CREATE VIRTUAL TABLE saved_posts_fts USING fts5(
      title, selftext, content='saved_posts', content_rowid='id'
    )
    """

    execute """
    CREATE TRIGGER saved_posts_ai AFTER INSERT ON saved_posts BEGIN
      INSERT INTO saved_posts_fts(rowid, title, selftext) VALUES (new.id, new.title, new.selftext);
    END
    """

    execute """
    CREATE TRIGGER saved_posts_ad AFTER DELETE ON saved_posts BEGIN
      INSERT INTO saved_posts_fts(saved_posts_fts, rowid, title, selftext) VALUES ('delete', old.id, old.title, old.selftext);
    END
    """

    execute """
    CREATE TRIGGER saved_posts_au AFTER UPDATE ON saved_posts BEGIN
      INSERT INTO saved_posts_fts(saved_posts_fts, rowid, title, selftext) VALUES ('delete', old.id, old.title, old.selftext);
      INSERT INTO saved_posts_fts(rowid, title, selftext) VALUES (new.id, new.title, new.selftext);
    END
    """
  end

  def down do
    execute "DROP TRIGGER IF EXISTS saved_posts_au"
    execute "DROP TRIGGER IF EXISTS saved_posts_ad"
    execute "DROP TRIGGER IF EXISTS saved_posts_ai"
    execute "DROP TABLE IF EXISTS saved_posts_fts"
  end
end
```

Run `mix ecto.gen.migration create_saved_posts_fts` for the filename, paste body in (this migration needs explicit `up/0`/`down/0`, not `change/0`, since triggers aren't reversible generically).

- [ ] **Step 2: Write the failing test**

Append to `test/reddit_saves_manager/saves_test.exs`:

```elixir
  test "search_posts/1 finds posts by title and body text" do
    {:ok, _} =
      Saves.upsert_saved_post(
        @valid_attrs
        |> Map.put(:title, "GenServer timeout tuning")
        |> Map.put(:selftext, "discussion of :hibernate")
      )

    {:ok, _} =
      Saves.upsert_saved_post(
        @valid_attrs
        |> Map.put(:reddit_fullname, "t3_zzz999")
        |> Map.put(:title, "Photo booth build")
        |> Map.put(:selftext, "DNP printer notes")
      )

    assert [found] = Saves.search_posts("GenServer")
    assert found.title == "GenServer timeout tuning"
  end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: FAIL — `search_posts/1` undefined.

- [ ] **Step 4: Implement `search_posts/1`**

Add to `lib/reddit_saves_manager/saves.ex`:

```elixir
  def search_posts(query_text) when is_binary(query_text) and query_text != "" do
    sql = """
    SELECT saved_posts.* FROM saved_posts
    JOIN saved_posts_fts ON saved_posts_fts.rowid = saved_posts.id
    WHERE saved_posts_fts MATCH ? AND saved_posts.archived_at IS NULL
    ORDER BY rank
    """

    {:ok, %{rows: rows, columns: columns}} = Repo.query(sql, [query_text])

    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
      |> then(&Repo.load(SavedPost, &1))
    end)
  end

  def search_posts(_), do: []
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: PASS (7 tests)

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations lib/reddit_saves_manager/saves.ex test/reddit_saves_manager/saves_test.exs
git commit -m "Add FTS5 full-text search over saved posts"
```

---

### Task 5: Reddit OAuth — token storage, client authorize/exchange/refresh, auth controller

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_reddit_tokens.exs`
- Create: `lib/reddit_saves_manager/reddit/token.ex`
- Create: `lib/reddit_saves_manager/reddit/client.ex`
- Create: `lib/reddit_saves_manager/reddit.ex`
- Create: `lib/reddit_saves_manager_web/controllers/auth_controller.ex`
- Modify: `lib/reddit_saves_manager_web/router.ex`
- Test: `test/reddit_saves_manager/reddit_test.exs`
- Test: `test/reddit_saves_manager/reddit/client_test.exs`

**Interfaces:**
- Produces: `Reddit.Client.authorize_url/1`, `exchange_code/1`, `refresh_token/1`, all returning `{:ok, map()} | {:error, term()}` with map keys `:access_token`, `:refresh_token`, `:expires_in`. `Reddit.save_token/1`, `Reddit.valid_access_token/0` -> `{:ok, String.t()} | {:error, :not_authenticated}`.

- [ ] **Step 1: Write the migration**

```elixir
defmodule RedditSavesManager.Repo.Migrations.CreateRedditTokens do
  use Ecto.Migration

  def change do
    create table(:reddit_tokens) do
      add :access_token, :string, null: false
      add :refresh_token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps()
    end
  end
end
```

Run `mix ecto.gen.migration create_reddit_tokens` for the filename, paste body in.

- [ ] **Step 2: Write the `Token` schema**

```elixir
defmodule RedditSavesManager.Reddit.Token do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reddit_tokens" do
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:access_token, :refresh_token, :expires_at])
    |> validate_required([:access_token, :refresh_token, :expires_at])
  end
end
```

- [ ] **Step 3: Write the failing test for `Reddit.Client` (authorize_url + exchange_code, mocked via Req.Test)**

```elixir
defmodule RedditSavesManager.Reddit.ClientTest do
  # async: false — this test stubs Req via a global Application env key
  # (:reddit_req_options), which every other test file touching the Reddit
  # client also mutates. Running those concurrently races on that shared,
  # process-independent state, so every test file that sets
  # :reddit_req_options or :open_router_req_options in this plan uses
  # async: false for the same reason.
  use ExUnit.Case, async: false
  alias RedditSavesManager.Reddit.Client

  setup do
    Application.put_env(:reddit_saves_manager, :reddit_req_options,
      plug: {Req.Test, Client}
    )

    :ok
  end

  test "authorize_url/1 builds a reddit authorize URL with the given state" do
    url = Client.authorize_url("xyz")
    assert url =~ "https://www.reddit.com/api/v1/authorize"
    assert url =~ "state=xyz"
  end

  test "exchange_code/1 returns access/refresh tokens on success" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => "atok",
        "refresh_token" => "rtok",
        "expires_in" => 3600
      })
    end)

    assert {:ok, %{access_token: "atok", refresh_token: "rtok", expires_in: 3600}} =
             Client.exchange_code("some-code")
  end

  test "refresh_token/1 returns a new access token" do
    Req.Test.stub(Client, fn conn ->
      Req.Test.json(conn, %{"access_token" => "newtok", "expires_in" => 3600})
    end)

    assert {:ok, %{access_token: "newtok", expires_in: 3600}} = Client.refresh_token("rtok")
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/reddit/client_test.exs`
Expected: FAIL — `RedditSavesManager.Reddit.Client` undefined.

- [ ] **Step 5: Implement `Reddit.Client`**

```elixir
defmodule RedditSavesManager.Reddit.Client do
  @authorize_endpoint "https://www.reddit.com/api/v1/authorize"
  @token_endpoint "https://www.reddit.com/api/v1/access_token"
  @api_base "https://oauth.reddit.com"

  defp config, do: Application.fetch_env!(:reddit_saves_manager, :reddit)
  defp req_options, do: Application.get_env(:reddit_saves_manager, :reddit_req_options, [])

  def authorize_url(state) do
    %{client_id: client_id, redirect_uri: redirect_uri} = config()

    query =
      URI.encode_query(%{
        "client_id" => client_id,
        "response_type" => "code",
        "state" => state,
        "redirect_uri" => redirect_uri,
        "duration" => "permanent",
        "scope" => "history save identity"
      })

    @authorize_endpoint <> "?" <> query
  end

  def exchange_code(code) do
    %{client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri} = config()

    body = %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri
    }

    post_token(body, client_id, client_secret)
  end

  def refresh_token(refresh_token) do
    %{client_id: client_id, client_secret: client_secret} = config()
    body = %{"grant_type" => "refresh_token", "refresh_token" => refresh_token}
    post_token(body, client_id, client_secret)
  end

  defp post_token(form_body, client_id, client_secret) do
    result =
      Req.post(
        [
          url: @token_endpoint,
          form: form_body,
          auth: {:basic, "#{client_id}:#{client_secret}"}
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           access_token: body["access_token"],
           refresh_token: body["refresh_token"],
           expires_in: body["expires_in"]
         }
         |> Map.reject(fn {_, v} -> is_nil(v) end)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_saved(access_token, username, after_cursor \\ nil) do
    params = if after_cursor, do: %{"after" => after_cursor, "limit" => 100}, else: %{"limit" => 100}

    result =
      Req.get(
        [
          url: @api_base <> "/user/#{username}/saved",
          params: params,
          auth: {:bearer, access_token}
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: %{"data" => %{"children" => children, "after" => after}}}} ->
        {:ok, %{children: Enum.map(children, & &1["data"]), after: after}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_comments(access_token, subreddit, post_id36) do
    result =
      Req.get(
        [
          url: @api_base <> "/r/#{subreddit}/comments/#{post_id36}",
          auth: {:bearer, access_token}
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: [_post_listing, %{"data" => %{"children" => children}}]}} ->
        comments =
          children
          |> Enum.filter(&(&1["kind"] == "t1"))
          |> Enum.map(fn %{"data" => d} ->
            %{author: d["author"], score: d["score"] || 0, body: d["body"] || ""}
          end)

        {:ok, comments}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def unsave(access_token, fullname) do
    result =
      Req.post(
        [
          url: @api_base <> "/api/unsave",
          form: %{"id" => fullname},
          auth: {:bearer, access_token}
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, {:unexpected_status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/reddit/client_test.exs`
Expected: PASS (3 tests)

- [ ] **Step 7: Write the failing test for the `Reddit` context (token storage + auto-refresh)**

```elixir
defmodule RedditSavesManager.RedditTest do
  use RedditSavesManager.DataCase
  alias RedditSavesManager.Reddit

  test "save_token/1 then valid_access_token/0 returns the stored token when not expired" do
    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
    {:ok, _} = Reddit.save_token(%{access_token: "atok", refresh_token: "rtok", expires_at: future})

    assert {:ok, "atok"} = Reddit.valid_access_token()
  end

  test "valid_access_token/0 returns :not_authenticated when no token stored" do
    assert {:error, :not_authenticated} = Reddit.valid_access_token()
  end
end
```

- [ ] **Step 8: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/reddit_test.exs`
Expected: FAIL — `Reddit` module undefined.

- [ ] **Step 9: Implement the `Reddit` context**

```elixir
defmodule RedditSavesManager.Reddit do
  alias RedditSavesManager.Repo
  alias RedditSavesManager.Reddit.{Token, Client}

  def get_token do
    Token |> Repo.all() |> List.first()
  end

  def save_token(attrs) do
    case get_token() do
      nil -> %Token{}
      existing -> existing
    end
    |> Token.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def valid_access_token do
    case get_token() do
      nil ->
        {:error, :not_authenticated}

      %Token{expires_at: expires_at} = token ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          {:ok, token.access_token}
        else
          refresh_and_store(token)
        end
    end
  end

  defp refresh_and_store(%Token{refresh_token: refresh_token}) do
    with {:ok, %{access_token: new_access_token, expires_in: expires_in}} <-
           Client.refresh_token(refresh_token) do
      expires_at =
        DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)

      {:ok, _} = save_token(%{access_token: new_access_token, refresh_token: refresh_token, expires_at: expires_at})
      {:ok, new_access_token}
    end
  end
end
```

- [ ] **Step 10: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/reddit_test.exs`
Expected: PASS (2 tests)

- [ ] **Step 11: Wire up the auth controller and routes**

`lib/reddit_saves_manager_web/controllers/auth_controller.ex`:

```elixir
defmodule RedditSavesManagerWeb.AuthController do
  use RedditSavesManagerWeb, :controller
  alias RedditSavesManager.Reddit
  alias RedditSavesManager.Reddit.Client

  def new(conn, _params) do
    state = Base.encode16(:crypto.strong_rand_bytes(8))

    conn
    |> put_session(:reddit_oauth_state, state)
    |> redirect(external: Client.authorize_url(state))
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    if get_session(conn, :reddit_oauth_state) == state do
      case Client.exchange_code(code) do
        {:ok, %{access_token: access_token, refresh_token: refresh_token, expires_in: expires_in}} ->
          expires_at =
            DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.truncate(:second)

          {:ok, _} = Reddit.save_token(%{access_token: access_token, refresh_token: refresh_token, expires_at: expires_at})

          conn
          |> put_flash(:info, "Connected to Reddit")
          |> redirect(to: ~p"/posts")

        {:error, reason} ->
          conn
          |> put_flash(:error, "Reddit auth failed: #{inspect(reason)}")
          |> redirect(to: ~p"/")
      end
    else
      conn
      |> put_flash(:error, "OAuth state mismatch")
      |> redirect(to: ~p"/")
    end
  end
end
```

In `lib/reddit_saves_manager_web/router.ex`, add inside the existing `scope "/", RedditSavesManagerWeb do` block (the one using the `:browser` pipeline):

```elixir
get "/auth/reddit", AuthController, :new
get "/auth/reddit/callback", AuthController, :callback
```

- [ ] **Step 12: Manually verify the OAuth flow**

Run: `mix phx.server`, visit `http://localhost:4000/auth/reddit`, log in and authorize on Reddit, confirm redirect back lands on `/posts` (404 is fine for now — Task 7 builds that page) with an "info" flash of "Connected to Reddit".

- [ ] **Step 13: Commit**

```bash
git add priv/repo/migrations lib/reddit_saves_manager/reddit.ex lib/reddit_saves_manager/reddit/ lib/reddit_saves_manager_web/controllers/auth_controller.ex lib/reddit_saves_manager_web/router.ex test/reddit_saves_manager/reddit_test.exs test/reddit_saves_manager/reddit/client_test.exs
git commit -m "Add Reddit OAuth: token storage, client, auth controller"
```

---

### Task 6: Reddit sync (fetch + upsert saved posts)

**Files:**
- Create: `lib/reddit_saves_manager/saves/sync.ex`
- Test: `test/reddit_saves_manager/saves/sync_test.exs`

**Interfaces:**
- Consumes: `Reddit.Client.fetch_saved/3` (Task 5), `Saves.upsert_saved_post/1` (Task 2)
- Produces: `Saves.Sync.run(access_token, username)` -> `{:ok, %{synced: integer()}}`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule RedditSavesManager.Saves.SyncTest do
  # async: false — stubs Req via the shared :reddit_req_options Application
  # env key (see the note in reddit/client_test.exs).
  use RedditSavesManager.DataCase, async: false
  alias RedditSavesManager.Saves
  alias RedditSavesManager.Saves.Sync
  alias RedditSavesManager.Reddit.Client

  setup do
    Application.put_env(:reddit_saves_manager, :reddit_req_options, plug: {Req.Test, Client})
    :ok
  end

  test "run/2 paginates through all saved posts and upserts them" do
    Req.Test.stub(Client, fn conn ->
      case conn.params["after"] do
        nil ->
          Req.Test.json(conn, %{
            "data" => %{
              "after" => "t3_page2",
              "children" => [
                %{"data" => %{"name" => "t3_a", "title" => "Post A", "subreddit" => "elixir", "permalink" => "/r/elixir/a/", "saved" => true, "created_utc" => 1_700_000_000}}
              ]
            }
          })

        "t3_page2" ->
          Req.Test.json(conn, %{
            "data" => %{
              "after" => nil,
              "children" => [
                %{"data" => %{"name" => "t3_b", "title" => "Post B", "subreddit" => "elixir", "permalink" => "/r/elixir/b/", "saved" => true, "created_utc" => 1_700_000_100}}
              ]
            }
          })
      end
    end)

    assert {:ok, %{synced: 2}} = Sync.run("atok", "sjkim")
    assert length(Saves.list_active_posts()) == 2
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/saves/sync_test.exs`
Expected: FAIL — `Sync` module undefined.

- [ ] **Step 3: Implement `Saves.Sync`**

```elixir
defmodule RedditSavesManager.Saves.Sync do
  alias RedditSavesManager.Reddit.Client
  alias RedditSavesManager.Saves

  def run(access_token, username) do
    synced = fetch_all(access_token, username, nil, 0)
    {:ok, %{synced: synced}}
  end

  defp fetch_all(access_token, username, after_cursor, acc) do
    case Client.fetch_saved(access_token, username, after_cursor) do
      {:ok, %{children: children, after: nil}} ->
        acc + upsert_all(children)

      {:ok, %{children: children, after: next_cursor}} ->
        fetch_all(access_token, username, next_cursor, acc + upsert_all(children))

      {:error, _reason} = error ->
        error
    end
  end

  defp upsert_all(children) do
    Enum.reduce(children, 0, fn data, count ->
      attrs = %{
        reddit_fullname: data["name"],
        type: if(String.starts_with?(data["name"], "t1_"), do: "comment", else: "link"),
        title: data["title"] || data["link_title"] || "(comment)",
        subreddit: data["subreddit"],
        url: data["url"],
        permalink: data["permalink"],
        author: data["author"],
        score: data["score"] || 0,
        created_utc: unix_to_datetime(data["created_utc"]),
        selftext: data["selftext"] || data["body"],
        saved_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      case Saves.upsert_saved_post(attrs) do
        {:ok, _} -> count + 1
        {:error, _} -> count
      end
    end)
  end

  defp unix_to_datetime(nil), do: nil

  defp unix_to_datetime(unix) do
    unix |> trunc() |> DateTime.from_unix!() |> DateTime.truncate(:second)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/saves/sync_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/reddit_saves_manager/saves/sync.ex test/reddit_saves_manager/saves/sync_test.exs
git commit -m "Add Reddit saved-posts sync (paginated fetch + upsert)"
```

---

### Task 7: `PostsLive.Index` — list, filters, and manual sync

**Files:**
- Create: `lib/reddit_saves_manager_web/live/posts_live/index.ex`
- Create: `lib/reddit_saves_manager_web/live/posts_live/index.html.heex`
- Modify: `lib/reddit_saves_manager_web/router.ex`
- Test: `test/reddit_saves_manager_web/live/posts_live_index_test.exs`

**Interfaces:**
- Consumes: `Saves.list_active_posts/1` (Task 3), `Saves.Sync.run/2` (Task 6), `Reddit.valid_access_token/0` (Task 5)
- Produces: the `/posts` route rendering the list; `assigns.posts`, `assigns.filters`

- [ ] **Step 1: Add the live route**

In `lib/reddit_saves_manager_web/router.ex`, inside the `:browser` scope, add:

```elixir
live "/posts", PostsLive.Index
```

- [ ] **Step 2: Write the failing LiveView test**

```elixir
defmodule RedditSavesManagerWeb.PostsLiveIndexTest do
  # async: false — the bulk-unsave test added in Task 9 stubs Req via the
  # shared :reddit_req_options Application env key (see the note in
  # reddit/client_test.exs).
  use RedditSavesManagerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias RedditSavesManager.Saves

  setup do
    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_abc",
        type: "link",
        title: "OTP kata notes",
        subreddit: "elixir",
        permalink: "/r/elixir/abc/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    %{post: post}
  end

  test "renders the list of active saved posts", %{conn: conn, post: post} do
    {:ok, _view, html} = live(conn, ~p"/posts")
    assert html =~ post.title
  end

  test "filters by subreddit", %{conn: conn} do
    {:ok, _} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_xyz",
        type: "link",
        title: "Photo booth printer specs",
        subreddit: "photography",
        permalink: "/r/photography/xyz/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/posts")

    html =
      view
      |> form("#filters-form", filters: %{subreddit: "photography"})
      |> render_submit()

    assert html =~ "Photo booth printer specs"
    refute html =~ "OTP kata notes"
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager_web/live/posts_live_index_test.exs`
Expected: FAIL — LiveView module/route missing.

- [ ] **Step 4: Implement `PostsLive.Index`**

```elixir
defmodule RedditSavesManagerWeb.PostsLive.Index do
  use RedditSavesManagerWeb, :live_view

  alias RedditSavesManager.Saves
  alias RedditSavesManager.Saves.Sync
  alias RedditSavesManager.Reddit

  def mount(_params, _session, socket) do
    {:ok, assign(socket, filters: %{}, posts: Saves.list_active_posts(), selected_ids: MapSet.new())}
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
```

`lib/reddit_saves_manager_web/live/posts_live/index.html.heex`:

```heex
<h1>Saved Posts</h1>

<button phx-click="sync">Sync now</button>

<.form for={%{}} as={:filters} id="filters-form" phx-submit="filter">
  <input type="text" name="filters[subreddit]" placeholder="subreddit" value={@filters[:subreddit]} />
  <input type="text" name="filters[type]" placeholder="type (link/comment)" value={@filters[:type]} />
  <input type="text" name="filters[tag]" placeholder="tag" value={@filters[:tag]} />
  <button type="submit">Filter</button>
</.form>

<ul>
  <li :for={post <- @posts}>
    <input
      type="checkbox"
      checked={MapSet.member?(@selected_ids, post.id)}
      phx-click="toggle_select"
      phx-value-id={post.id}
    />
    <.link navigate={~p"/posts/#{post.id}"}><%= post.title %></.link>
    (<%= post.subreddit %>)
  </li>
</ul>
```

- [ ] **Step 5: Add `username` to Reddit env config**

In `config/runtime.exs`, add `username: env!("REDDIT_USERNAME", :string)` to the `:reddit` config block, and add `REDDIT_USERNAME=` to `.env.example` / your real `.env`.

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager_web/live/posts_live_index_test.exs`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lib/reddit_saves_manager_web/live/posts_live lib/reddit_saves_manager_web/router.ex config/runtime.exs .env.example test/reddit_saves_manager_web/live/posts_live_index_test.exs
git commit -m "Add PostsLive.Index: list, filters, manual sync"
```

---

### Task 8: Search box and inline tagging in `PostsLive.Index`

**Files:**
- Modify: `lib/reddit_saves_manager_web/live/posts_live/index.ex`
- Modify: `lib/reddit_saves_manager_web/live/posts_live/index.html.heex`
- Modify: `test/reddit_saves_manager_web/live/posts_live_index_test.exs`

**Interfaces:**
- Consumes: `Saves.search_posts/1` (Task 4), `Saves.tag_post/2`, `Saves.list_tags_for_post/1` (Task 3)

- [ ] **Step 1: Write the failing tests**

Append to `test/reddit_saves_manager_web/live/posts_live_index_test.exs`:

```elixir
  test "search box filters by full-text match", %{conn: conn} do
    {:ok, _} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_search1",
        type: "link",
        title: "Deep dive on Erlang schedulers",
        subreddit: "erlang",
        permalink: "/r/erlang/1/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/posts")

    html =
      view
      |> form("#search-form", search: %{query: "schedulers"})
      |> render_submit()

    assert html =~ "Deep dive on Erlang schedulers"
    refute html =~ "OTP kata notes"
  end

  test "tagging a post from the list", %{conn: conn, post: post} do
    {:ok, view, _html} = live(conn, ~p"/posts")

    html =
      view
      |> form("#tag-form-#{post.id}", tag: %{name: "research"})
      |> render_submit()

    assert html =~ "research"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reddit_saves_manager_web/live/posts_live_index_test.exs`
Expected: FAIL — no `#search-form`/`#tag-form-*` elements, no `search`/`add_tag` events.

- [ ] **Step 3: Implement search and tagging events**

Add to `lib/reddit_saves_manager_web/live/posts_live/index.ex`:

```elixir
  def handle_event("search", %{"search" => %{"query" => ""}}, socket) do
    {:noreply, assign(socket, posts: Saves.list_active_posts(socket.assigns.filters))}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, assign(socket, posts: Saves.search_posts(query))}
  end

  def handle_event("add_tag", %{"post_id" => post_id, "tag" => %{"name" => name}}, socket)
      when name != "" do
    {:ok, _} = Saves.tag_post(String.to_integer(post_id), name)
    {:noreply, assign(socket, posts: Saves.list_active_posts(socket.assigns.filters))}
  end
```

Add to the `.heex` template, above the `<ul>`:

```heex
<.form for={%{}} as={:search} id="search-form" phx-submit="search">
  <input type="text" name="search[query]" placeholder="search title/body" />
  <button type="submit">Search</button>
</.form>
```

Inside the `<li>` loop, after the post link, add:

```heex
<.form for={%{}} as={:tag} id={"tag-form-#{post.id}"} phx-submit="add_tag">
  <input type="hidden" name="post_id" value={post.id} />
  <input type="text" name="tag[name]" placeholder="add tag" />
  <button type="submit">Tag</button>
</.form>
<span :for={tag <- Saves.list_tags_for_post(post.id)}><%= tag.name %></span>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reddit_saves_manager_web/live/posts_live_index_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/reddit_saves_manager_web/live/posts_live test/reddit_saves_manager_web/live/posts_live_index_test.exs
git commit -m "Add search box and inline tagging to PostsLive.Index"
```

---

### Task 9: Bulk-select unsave

**Files:**
- Modify: `lib/reddit_saves_manager/saves.ex`
- Modify: `lib/reddit_saves_manager_web/live/posts_live/index.ex`
- Modify: `lib/reddit_saves_manager_web/live/posts_live/index.html.heex`
- Modify: `test/reddit_saves_manager/saves_test.exs`
- Modify: `test/reddit_saves_manager_web/live/posts_live_index_test.exs`

**Interfaces:**
- Consumes: `Reddit.Client.unsave/2` (Task 5), `Reddit.valid_access_token/0` (Task 5), `Saves.archive_posts/1` (Task 2)
- Produces: `Saves.unsave_posts/2` (access_token, list of `SavedPost` ids) -> `{:ok, %{unsaved: [id], failed: [id]}}`

- [ ] **Step 1: Write the failing test for `Saves.unsave_posts/2`**

Append to `test/reddit_saves_manager/saves_test.exs`:

```elixir
  test "unsave_posts/2 archives posts that succeed and reports failures" do
    Application.put_env(:reddit_saves_manager, :reddit_req_options,
      plug: {Req.Test, RedditSavesManager.Reddit.Client}
    )

    {:ok, post1} = Saves.upsert_saved_post(@valid_attrs)
    {:ok, post2} = Saves.upsert_saved_post(%{@valid_attrs | reddit_fullname: "t3_fail"})

    Req.Test.stub(RedditSavesManager.Reddit.Client, fn conn ->
      %{"id" => id} = conn.body_params

      if id == "t3_abc123" do
        Plug.Conn.send_resp(conn, 200, "{}")
      else
        Plug.Conn.send_resp(conn, 500, "{}")
      end
    end)

    assert {:ok, %{unsaved: unsaved, failed: failed}} =
             Saves.unsave_posts("faketoken", [post1.id, post2.id])

    assert post1.id in unsaved
    assert post2.id in failed
    assert Saves.list_active_posts() |> Enum.map(& &1.id) == [post2.id]
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: FAIL — `unsave_posts/2` undefined.

- [ ] **Step 3: Implement `Saves.unsave_posts/2`**

Add to `lib/reddit_saves_manager/saves.ex`:

```elixir
  alias RedditSavesManager.Reddit.Client

  def unsave_posts(access_token, ids) when is_list(ids) do
    posts = Enum.map(ids, &get_saved_post!/1)

    {succeeded, failed} =
      Enum.split_with(posts, fn post ->
        Client.unsave(access_token, post.reddit_fullname) == :ok
      end)

    succeeded_ids = Enum.map(succeeded, & &1.id)
    failed_ids = Enum.map(failed, & &1.id)

    if succeeded_ids != [], do: archive_posts(succeeded_ids)

    {:ok, %{unsaved: succeeded_ids, failed: failed_ids}}
  end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/saves_test.exs`
Expected: PASS

- [ ] **Step 5: Wire the bulk-unsave button into `PostsLive.Index`**

Add to `lib/reddit_saves_manager_web/live/posts_live/index.ex`:

```elixir
  def handle_event("bulk_unsave", _params, socket) do
    case Reddit.valid_access_token() do
      {:ok, access_token} ->
        ids = MapSet.to_list(socket.assigns.selected_ids)
        {:ok, %{unsaved: unsaved, failed: failed}} = Saves.unsave_posts(access_token, ids)

        message =
          if failed == [] do
            "Unsaved #{length(unsaved)} posts"
          else
            "Unsaved #{length(unsaved)}, failed on #{length(failed)}"
          end

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(posts: Saves.list_active_posts(socket.assigns.filters), selected_ids: MapSet.new())}

      {:error, :not_authenticated} ->
        {:noreply, put_flash(socket, :error, "Connect your Reddit account first")}
    end
  end
```

Add to the `.heex` template, below the filter form:

```heex
<button phx-click="bulk_unsave" disabled={MapSet.size(@selected_ids) == 0}>
  Unsave selected (<%= MapSet.size(@selected_ids) %>)
</button>
```

- [ ] **Step 6: Write and run a LiveView test for bulk-unsave**

Append to `test/reddit_saves_manager_web/live/posts_live_index_test.exs`:

```elixir
  test "bulk unsave archives selected posts", %{conn: conn, post: post} do
    Application.put_env(:reddit_saves_manager, :reddit_req_options,
      plug: {Req.Test, RedditSavesManager.Reddit.Client}
    )

    Req.Test.stub(RedditSavesManager.Reddit.Client, fn conn ->
      Plug.Conn.send_resp(conn, 200, "{}")
    end)

    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
    {:ok, _} = RedditSavesManager.Reddit.save_token(%{access_token: "atok", refresh_token: "rtok", expires_at: future})

    {:ok, view, _html} = live(conn, ~p"/posts")

    view |> element("input[phx-value-id='#{post.id}']") |> render_click()
    html = view |> element("button", "Unsave selected") |> render_click()

    refute html =~ post.title
  end
```

Run: `mix test test/reddit_saves_manager_web/live/posts_live_index_test.exs`
Expected: PASS (all tests in file)

- [ ] **Step 7: Commit**

```bash
git add lib/reddit_saves_manager/saves.ex lib/reddit_saves_manager_web/live/posts_live test/reddit_saves_manager/saves_test.exs test/reddit_saves_manager_web/live/posts_live_index_test.exs
git commit -m "Add bulk-select unsave to PostsLive.Index"
```

---

### Task 10: `Reddit.Client.fetch_comments/3` comment flattening helper

**Files:**
- Modify: `lib/reddit_saves_manager/reddit/client.ex` (already has `fetch_comments/3` from Task 5 — this task adds the top-N helper used by Research)
- Create: `lib/reddit_saves_manager/research.ex` (stub with just the helper; full context filled in Task 11)
- Test: `test/reddit_saves_manager/research_test.exs`

**Interfaces:**
- Consumes: `Reddit.Client.fetch_comments/3` (Task 5, returns list of `%{author, score, body}`)
- Produces: `Research.top_comments(comments, n)` -> list of the top `n` comments by score, descending

- [ ] **Step 1: Write the failing test**

```elixir
defmodule RedditSavesManager.ResearchTest do
  use ExUnit.Case, async: true
  alias RedditSavesManager.Research
  # Note for Task 11: this module is upgraded to `use RedditSavesManager.DataCase,
  # async: false` there (generate_and_save/2 touches the DB and stubs Req via
  # shared Application env keys — see the note in reddit/client_test.exs).

  test "top_comments/2 sorts by score descending and takes n" do
    comments = [
      %{author: "a", score: 5, body: "meh"},
      %{author: "b", score: 42, body: "great point"},
      %{author: "c", score: 10, body: "also good"}
    ]

    assert [%{author: "b"}, %{author: "c"}] = Research.top_comments(comments, 2)
  end

  test "top_comments/2 returns all comments if n exceeds count" do
    comments = [%{author: "a", score: 1, body: "x"}]
    assert [%{author: "a"}] = Research.top_comments(comments, 50)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/research_test.exs`
Expected: FAIL — `Research` module undefined.

- [ ] **Step 3: Implement the helper**

```elixir
defmodule RedditSavesManager.Research do
  def top_comments(comments, n) do
    comments
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(n)
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/research_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/reddit_saves_manager/research.ex test/reddit_saves_manager/research_test.exs
git commit -m "Add comment top-N sorting helper to Research context"
```

---

### Task 11: OpenRouter client, prompt builder, and `research_docs` persistence

**Files:**
- Create: `priv/repo/migrations/<timestamp>_create_research_docs.exs`
- Create: `lib/reddit_saves_manager/research/doc.ex`
- Create: `lib/reddit_saves_manager/research/open_router_client.ex`
- Modify: `lib/reddit_saves_manager/research.ex`
- Test: `test/reddit_saves_manager/research/open_router_client_test.exs`
- Test: `test/reddit_saves_manager/research_test.exs`

**Interfaces:**
- Consumes: `Saves.SavedPost` (Task 2), `Reddit.Client.fetch_comments/3` + `Reddit.valid_access_token/0` (Task 5), `Research.top_comments/2` (Task 10)
- Produces: `Research.OpenRouterClient.generate(prompt)` -> `{:ok, String.t()} | {:error, term()}`; `Research.build_prompt/2`; `Research.generate_and_save/2` (`SavedPost`, comment_count) -> `{:ok, %Research.Doc{}} | {:error, term()}`

- [ ] **Step 1: Write the migration**

```elixir
defmodule RedditSavesManager.Repo.Migrations.CreateResearchDocs do
  use Ecto.Migration

  def change do
    create table(:research_docs) do
      add :saved_post_id, references(:saved_posts, on_delete: :delete_all), null: false
      add :file_path, :string, null: false
      add :comment_count_used, :integer, null: false
      add :model, :string, null: false
      add :generated_at, :utc_datetime, null: false

      timestamps()
    end

    create index(:research_docs, [:saved_post_id])
  end
end
```

Run `mix ecto.gen.migration create_research_docs` for the filename, paste body in.

- [ ] **Step 2: Write the `Doc` schema**

```elixir
defmodule RedditSavesManager.Research.Doc do
  use Ecto.Schema
  import Ecto.Changeset

  schema "research_docs" do
    field :file_path, :string
    field :comment_count_used, :integer
    field :model, :string
    field :generated_at, :utc_datetime
    belongs_to :saved_post, RedditSavesManager.Saves.SavedPost

    timestamps()
  end

  def changeset(doc, attrs) do
    doc
    |> cast(attrs, [:saved_post_id, :file_path, :comment_count_used, :model, :generated_at])
    |> validate_required([:saved_post_id, :file_path, :comment_count_used, :model, :generated_at])
  end
end
```

- [ ] **Step 3: Write the failing test for `OpenRouterClient`**

```elixir
defmodule RedditSavesManager.Research.OpenRouterClientTest do
  # async: false — stubs Req via the shared :open_router_req_options
  # Application env key (see the note in reddit/client_test.exs; the same
  # global-state hazard applies here).
  use ExUnit.Case, async: false
  alias RedditSavesManager.Research.OpenRouterClient

  setup do
    Application.put_env(:reddit_saves_manager, :open_router_req_options,
      plug: {Req.Test, OpenRouterClient}
    )

    :ok
  end

  test "generate/1 returns the model's markdown content on success" do
    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{
        "choices" => [%{"message" => %{"content" => "# Research Doc\n\nSummary here."}}]
      })
    end)

    assert {:ok, "# Research Doc\n\nSummary here."} = OpenRouterClient.generate("some prompt")
  end

  test "generate/1 returns an error on non-200 response" do
    Req.Test.stub(OpenRouterClient, fn conn ->
      Plug.Conn.send_resp(conn, 500, "{}")
    end)

    assert {:error, _} = OpenRouterClient.generate("some prompt")
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager/research/open_router_client_test.exs`
Expected: FAIL — `OpenRouterClient` undefined.

- [ ] **Step 5: Implement `OpenRouterClient`**

```elixir
defmodule RedditSavesManager.Research.OpenRouterClient do
  @endpoint "https://openrouter.ai/api/v1/chat/completions"

  defp config, do: Application.fetch_env!(:reddit_saves_manager, :open_router)
  defp req_options, do: Application.get_env(:reddit_saves_manager, :open_router_req_options, [])

  def model, do: config()[:model]

  def generate(prompt) do
    %{api_key: api_key, model: model} = config()

    result =
      Req.post(
        [
          url: @endpoint,
          json: %{
            "model" => model,
            "messages" => [%{"role" => "user", "content" => prompt}]
          },
          auth: {:bearer, api_key}
        ] ++ req_options()
      )

    case result do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_status, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

- [ ] **Step 6: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager/research/open_router_client_test.exs`
Expected: PASS

- [ ] **Step 7: Write the failing test for `Research.build_prompt/2` and `Research.generate_and_save/2`**

Append to `test/reddit_saves_manager/research_test.exs` (change `use ExUnit.Case, async: true` to `use RedditSavesManager.DataCase, async: false` — `generate_and_save/2` touches the DB and stubs Req via shared Application env keys):

```elixir
  alias RedditSavesManager.Saves
  alias RedditSavesManager.Reddit.Client, as: RedditClient
  alias RedditSavesManager.Research.OpenRouterClient

  test "build_prompt/2 includes post title, url, and comment bodies" do
    post = %Saves.SavedPost{title: "OTP kata notes", url: "https://reddit.com/x", subreddit: "elixir", selftext: "some body"}
    comments = [%{author: "a", score: 10, body: "great insight"}]

    prompt = RedditSavesManager.Research.build_prompt(post, comments)

    assert prompt =~ "OTP kata notes"
    assert prompt =~ "https://reddit.com/x"
    assert prompt =~ "great insight"
  end

  test "generate_and_save/2 fetches comments, calls OpenRouter, writes a file, and records metadata" do
    tmp_dir = System.tmp_dir!() |> Path.join("reddit_research_test_#{System.unique_integer([:positive])}")
    Application.put_env(:reddit_saves_manager, :research_output_dir, tmp_dir)

    Application.put_env(:reddit_saves_manager, :reddit_req_options, plug: {Req.Test, RedditClient})
    Application.put_env(:reddit_saves_manager, :open_router_req_options, plug: {Req.Test, OpenRouterClient})

    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
    {:ok, _} = RedditSavesManager.Reddit.save_token(%{access_token: "atok", refresh_token: "rtok", expires_at: future})

    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_res1",
        type: "link",
        title: "OTP kata notes",
        subreddit: "elixir",
        permalink: "/r/elixir/comments/res1/otp_kata_notes/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    Req.Test.stub(RedditClient, fn conn ->
      Req.Test.json(conn, [%{}, %{"data" => %{"children" => [%{"kind" => "t1", "data" => %{"author" => "a", "score" => 10, "body" => "great insight"}}]}}])
    end)

    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "# Doc\n\nContent"}}]})
    end)

    assert {:ok, doc} = RedditSavesManager.Research.generate_and_save(post, 5)
    assert doc.comment_count_used == 5
    assert File.exists?(doc.file_path)
    assert File.read!(doc.file_path) =~ "# Doc"
  end
```

- [ ] **Step 8: Run tests to verify they fail**

Run: `mix test test/reddit_saves_manager/research_test.exs`
Expected: FAIL — `build_prompt/2`, `generate_and_save/2` undefined.

- [ ] **Step 9: Implement `build_prompt/2` and `generate_and_save/2`**

Replace `lib/reddit_saves_manager/research.ex` with:

```elixir
defmodule RedditSavesManager.Research do
  alias RedditSavesManager.Repo
  alias RedditSavesManager.Reddit
  alias RedditSavesManager.Reddit.Client, as: RedditClient
  alias RedditSavesManager.Research.{Doc, OpenRouterClient}

  def top_comments(comments, n) do
    comments
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(n)
  end

  def build_prompt(post, comments) do
    comments_text =
      comments
      |> Enum.map(fn c -> "- (score #{c.score}) #{c.author}: #{c.body}" end)
      |> Enum.join("\n")

    """
    You are producing a clean, well-structured markdown research document from a Reddit thread.

    Post title: #{post.title}
    Subreddit: r/#{post.subreddit}
    URL: #{post.url}

    Post body:
    #{post.selftext}

    Top comments (sorted by score):
    #{comments_text}

    Write a markdown document that summarizes the key insights, points of debate, and
    actionable takeaways from this thread. Use headers and bullet points. Synthesize
    the comments rather than repeating them verbatim.
    """
  end

  def generate_and_save(post, comment_count) do
    with {:ok, access_token} <- Reddit.valid_access_token(),
         post_id36 <- post.reddit_fullname |> String.split("_", parts: 2) |> List.last(),
         {:ok, comments} <- RedditClient.fetch_comments(access_token, post.subreddit, post_id36),
         top <- top_comments(comments, comment_count),
         prompt <- build_prompt(post, top),
         {:ok, markdown} <- OpenRouterClient.generate(prompt),
         {:ok, file_path} <- write_doc_file(post, markdown) do
      %Doc{}
      |> Doc.changeset(%{
        saved_post_id: post.id,
        file_path: file_path,
        comment_count_used: comment_count,
        model: OpenRouterClient.model(),
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()
    end
  end

  defp write_doc_file(post, markdown) do
    dir = Application.get_env(:reddit_saves_manager, :research_output_dir, Path.expand("~/reddit-research"))
    File.mkdir_p!(dir)

    slug =
      post.title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    file_path = Path.join(dir, "#{slug}.md")

    frontmatter = """
    ---
    title: "#{post.title}"
    url: "#{post.url}"
    subreddit: "#{post.subreddit}"
    date: "#{Date.utc_today()}"
    tags: []
    ---

    """

    File.write!(file_path, frontmatter <> markdown)
    {:ok, file_path}
  end
end
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `mix test test/reddit_saves_manager/research_test.exs`
Expected: PASS

- [ ] **Step 11: Commit**

```bash
git add priv/repo/migrations lib/reddit_saves_manager/research.ex lib/reddit_saves_manager/research/ test/reddit_saves_manager/research
git commit -m "Add OpenRouter client and research-doc generation/persistence"
```

---

### Task 12: `PostsLive.Show` — post detail with on-demand research doc generation

**Files:**
- Create: `lib/reddit_saves_manager_web/live/posts_live/show.ex`
- Create: `lib/reddit_saves_manager_web/live/posts_live/show.html.heex`
- Modify: `lib/reddit_saves_manager_web/router.ex`
- Test: `test/reddit_saves_manager_web/live/posts_live_show_test.exs`

**Interfaces:**
- Consumes: `Saves.get_saved_post!/1` (Task 2), `Research.generate_and_save/2` (Task 11)

- [ ] **Step 1: Add the live route**

In `lib/reddit_saves_manager_web/router.ex`, inside the `:browser` scope:

```elixir
live "/posts/:id", PostsLive.Show
```

- [ ] **Step 2: Write the failing test**

```elixir
defmodule RedditSavesManagerWeb.PostsLiveShowTest do
  # async: false — the doc-generation test stubs Req via shared
  # :reddit_req_options / :open_router_req_options Application env keys
  # (see the note in reddit/client_test.exs).
  use RedditSavesManagerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias RedditSavesManager.Saves
  alias RedditSavesManager.Reddit.Client, as: RedditClient
  alias RedditSavesManager.Research.OpenRouterClient

  setup do
    {:ok, post} =
      Saves.upsert_saved_post(%{
        reddit_fullname: "t3_show1",
        type: "link",
        title: "Show page post",
        subreddit: "elixir",
        permalink: "/r/elixir/comments/show1/show_page_post/",
        saved_at: ~U[2026-01-01 00:00:00Z]
      })

    %{post: post}
  end

  test "renders the post title and body", %{conn: conn, post: post} do
    {:ok, _view, html} = live(conn, ~p"/posts/#{post.id}")
    assert html =~ post.title
  end

  test "generating a research doc shows a success flash", %{conn: conn, post: post} do
    tmp_dir = System.tmp_dir!() |> Path.join("reddit_research_show_test_#{System.unique_integer([:positive])}")
    Application.put_env(:reddit_saves_manager, :research_output_dir, tmp_dir)
    Application.put_env(:reddit_saves_manager, :reddit_req_options, plug: {Req.Test, RedditClient})
    Application.put_env(:reddit_saves_manager, :open_router_req_options, plug: {Req.Test, OpenRouterClient})

    future = DateTime.add(DateTime.utc_now(), 3600, :second) |> DateTime.truncate(:second)
    {:ok, _} = RedditSavesManager.Reddit.save_token(%{access_token: "atok", refresh_token: "rtok", expires_at: future})

    Req.Test.stub(RedditClient, fn conn ->
      Req.Test.json(conn, [%{}, %{"data" => %{"children" => []}}])
    end)

    Req.Test.stub(OpenRouterClient, fn conn ->
      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "# Doc"}}]})
    end)

    {:ok, view, _html} = live(conn, ~p"/posts/#{post.id}")

    html =
      view
      |> form("#generate-doc-form", doc: %{comment_count: "10"})
      |> render_submit()

    assert html =~ "Research doc generated"
  end
end
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mix test test/reddit_saves_manager_web/live/posts_live_show_test.exs`
Expected: FAIL — route/module missing.

- [ ] **Step 4: Implement `PostsLive.Show`**

```elixir
defmodule RedditSavesManagerWeb.PostsLive.Show do
  use RedditSavesManagerWeb, :live_view

  alias RedditSavesManager.Saves
  alias RedditSavesManager.Research

  def mount(%{"id" => id}, _session, socket) do
    post = Saves.get_saved_post!(id)
    {:ok, assign(socket, post: post)}
  end

  def handle_event("generate_doc", %{"doc" => %{"comment_count" => comment_count}}, socket) do
    comment_count = String.to_integer(comment_count)

    case Research.generate_and_save(socket.assigns.post, comment_count) do
      {:ok, doc} ->
        {:noreply, put_flash(socket, :info, "Research doc generated: #{doc.file_path}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Doc generation failed: #{inspect(reason)}")}
    end
  end
end
```

`lib/reddit_saves_manager_web/live/posts_live/show.html.heex`:

```heex
<h1><%= @post.title %></h1>
<p><%= @post.subreddit %> — <a href={@post.url}><%= @post.url %></a></p>
<p><%= @post.selftext %></p>

<.form for={%{}} as={:doc} id="generate-doc-form" phx-submit="generate_doc">
  <label for="comment_count">Number of top comments to include</label>
  <input type="number" name="doc[comment_count]" id="comment_count" value="20" min="1" />
  <button type="submit">Generate research doc</button>
</.form>
```

- [ ] **Step 5: Run test to verify it passes**

Run: `mix test test/reddit_saves_manager_web/live/posts_live_show_test.exs`
Expected: PASS

- [ ] **Step 6: Run the full test suite**

Run: `mix test`
Expected: all tests PASS

- [ ] **Step 7: Commit**

```bash
git add lib/reddit_saves_manager_web/live/posts_live lib/reddit_saves_manager_web/router.ex test/reddit_saves_manager_web/live/posts_live_show_test.exs
git commit -m "Add PostsLive.Show with on-demand research doc generation"
```

---

## Post-plan manual check (not a task — do this yourself once implementation is done)

Run `mix phx.server`, visit `/auth/reddit` to connect your real Reddit account, click "Sync now" on `/posts`, confirm your real saved posts appear, tag/filter/search a few, bulk-unsave one test post, and generate one real research doc end-to-end to confirm the OpenRouter call and file write work against the live APIs (all prior testing used mocked HTTP).
