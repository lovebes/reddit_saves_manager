# Reddit Saves Manager — Design

> **2026-09-06 update:** Reddit's Responsible Builder Policy denies this
> app's OAuth app the scopes it needs, so the OAuth/API sections below
> (Reddit sync, unsave, comment-tree fetch) are superseded. Saved posts,
> unsaving, and comment fetching are now done by driving a real browser
> session (Claude's browser tool) against reddit.com directly, and loading
> results into the app via `mix reddit.ingest_saved` (saved posts) or by
> pasting comments JSON into the research-doc form (comment fetch). See
> `lib/mix/tasks/reddit.ingest_saved.ex` for the exact contract. Bulk
> "unsave" in the app now only archives locally; removing from Reddit
> itself is a separate browser-driven action done on request. The Reddit
> OAuth token storage, client, and auth controller have been deleted.

## Purpose

A personal, local-only tool to manage Reddit "saved" posts/comments: browse,
tag, search, and bulk-unsave them (Reddit's native saved list is an
unsearchable, unorganized dump), plus generate AI-written markdown research
documents from a saved post and its top comments.

Not a product. Single user (SJ only). No hosting, no public auth surface.

## Stack

- Elixir + Phoenix LiveView
- SQLite via Ecto (single file DB)
- `dotenvy` (or equivalent) to load `.env` into `System` env at boot;
  `config/runtime.exs` reads secrets via `System.fetch_env!/1`
- Reddit OAuth2, "installed app" type, authorization-code flow, redirect to
  `http://localhost:PORT/auth/reddit/callback`
- OpenRouter API for research-doc generation (model configurable via env)

## Data model

- `saved_posts`
  - `reddit_fullname` (unique) — Reddit's `t3_*`/`t1_*` id, used for dedup on sync
  - `type` — `:link` or `:comment`
  - `title`, `subreddit`, `url`, `permalink`, `author`, `score`, `created_utc`
  - `selftext` / body
  - `saved_at`
  - `archived_at` (nullable) — set when unsaved via the app; row is kept for
    history but excluded from the active list
- `tags`
  - `name`
- `post_tags` — join table, `saved_post_id` + `tag_id`
- `research_docs` — metadata only, generated content lives on disk
  - `saved_post_id`
  - `file_path`
  - `comment_count_used`
  - `model`
  - `generated_at`

SQLite FTS5 virtual table indexing `title` + `selftext` on `saved_posts` for
full-text search.

## Reddit sync (manual)

A "Sync now" button in the LiveView UI calls Reddit's
`GET /user/{username}/saved`, paginating through all results, and upserts
each item into `saved_posts` keyed on `reddit_fullname`. No background
scheduler — sync is user-triggered only. (A periodic sync is a trivial
future add-on if it turns out to be wanted; not built now.)

## Organize & declutter (LiveView)

- List view of active (non-archived) saved posts
- Filters: subreddit, type (link/comment), date range, tag
- Full-text search box (FTS5) across title + body
- Inline tagging (create/apply tags to a post)
- Multi-select + bulk "Unsave":
  - Calls Reddit's `POST /api/unsave` for each selected post
  - On success, sets `archived_at` locally; post drops out of the active
    list but the row remains in the DB

## AI research doc generation (on-demand, per post)

Triggered from a single post's detail view:

1. User sets "number of top comments to include" for this generation (no
   fixed default enforced by the system beyond a sane UI suggestion, e.g.
   20 — user can change it per post since thread quality/size varies)
2. Fetch the full comment tree for that post via Reddit's API
3. Flatten comments, sort by score descending, take the top N selected
4. Build a prompt containing: post title, post body/URL, subreddit, and the
   selected comments (author + score + body)
5. Send to OpenRouter (configured model) with a prompt template instructing
   it to produce a clean, well-structured markdown research document
6. Write the result to `~/reddit-research/<slug>.md` with YAML frontmatter:
   `title`, `url`, `subreddit`, `date`, `tags`
7. Record a `research_docs` row (file path, comment count used, model,
   timestamp) for in-app reference; the file on disk is the source of truth
   for content

## Error handling

- Reddit API errors during sync (rate limit, auth expiry): surface as a
  LiveView flash message; sync is idempotent so it's safe to retry
- Reddit token refresh: standard OAuth2 refresh-token flow; access/refresh
  tokens are stored in the local SQLite DB (single-user, local-only tool,
  so this is a low-severity concern) and are never written to logs
- OpenRouter failures (timeout, bad response): flash error, no partial file
  written (write only on full success)
- Unsave API failure for an individual post in a bulk action: that post
  keeps `archived_at` unset and is reported in the flash message as failed;
  the rest of the batch proceeds

## Testing

- Mocked Reddit HTTP client for unit tests (sync pagination, dedup,
  unsave calls)
- Ecto context tests: sync upsert logic, tagging, archive-on-unsave,
  FTS5 search
- LiveView tests: list/filter/search flow, bulk-select + unsave, per-post
  research-doc generation flow (OpenRouter client mocked)

## Out of scope (explicitly not building)

- Hosting/deployment (local only)
- Multi-user auth
- Scheduled/background sync
- A fixed/enforced comment-count default — always user-selected per doc
