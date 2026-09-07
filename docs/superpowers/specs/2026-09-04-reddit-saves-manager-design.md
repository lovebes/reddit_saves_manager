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
>
> **Finding the saved-posts page:** `reddit.com/saved` (no username) 404s —
> there's no session-relative shortcut. The correct URL always requires the
> username: `reddit.com/user/<username>/saved/`. No logged-in-profile menu
> was discoverable via the accessibility tree to derive the username
> programmatically, so it has to be supplied (config `REDDIT_USERNAME` or
> asked directly) rather than looked up. Current value: `lovebes`.
>
> **2026-09-07 update — scrape methodology + progress (resumable):**
>
> **Enumerating the saved list:** `www.reddit.com/user/<u>/saved/`'s
> virtualized feed is unreliable for bulk scrolling (blanks out, loses
> position, unmounts items already scrolled past). Use
> `old.reddit.com/user/<u>/saved/` instead — server-rendered, paginated
> (`?count=N&after=<fullname>`, follow the actual "next ›" link rather than
> guessing the `after` param), 25 items/page, stable. Saved-list order is
> **save order, not content date** — old items the user re-saved for
> reference sit interleaved with brand-new ones (e.g. a 12-year-old comment
> appeared between two 1-year-old posts), so there is no clean point where
> "this year's saves" end and older ones begin. Decision: keep going in
> save-list order continuously rather than trying to filter by date.
>
> **Scraping each item — required method:** click the title (or, from
> old.reddit, the "full comments (N)" link, not the truncated `context=3`
> single-comment view) to land on the actual post page, **then** capture
> the description and comments from that page. Do not rely on the saved-list
> page's inline preview text — that's how the first pass under-captured
> comments and had to be redone. Once on the post page, append `?sort=top`
> and use `get_page_text` for the description + comment section.
>
> **`get_page_text` fails on some posts** — returns just `"Check Claude
> service status."` or similarly wrong single-line content instead of the
> real post. Confirmed on: `v.redd.it` video posts, and (consistently) any
> `r/ClaudeAI` post — that subreddit's sidebar apparently has a "Check
> Claude service status" link and the tool's article-detection latches onto
> that instead of the real post content. Fallback when this happens: use
> `find` to locate the post-body paragraphs / target comment, then
> `computer` with `scroll_to` on that element's ref (plain mouse-wheel
> `scroll` action gets stuck not-advancing on some of these pages) followed
> by a `screenshot`, reading the text visually. `r/ClaudeAI` posts with 200+
> comments often have an auto-mod "TL;DR of the discussion generated
> automatically after 200 comments" stickied comment — read that instead of
> transcribing the whole thread, it's a genuine time-saver.
>
> **Capture depth ("couple of pages" per item):** full verbatim post
> title/body, plus a condensed-but-substantive transcription of roughly the
> top comments in "Top" sort order (not literally every reply on huge
> threads — hundreds of comments get condensed to the throughlines, small
> threads get transcribed close to verbatim).
>
> **Progress so far: posts 1–15 of the saved list are ingested**, in order,
> no gaps (verify count: `sqlite3 reddit_saves_manager_dev.db "SELECT
> count(*) FROM saved_posts;"`). Scraped JSON batches used for
> `mix reddit.ingest_saved` live in the session's scratchpad
> (`saved.json`, `saved2.json`, `saved3.json` — not committed, session-local
> temp files, would need re-scraping if lost). Items 1–15, in list order:
> 1. [comment] mini_ster reply to lovebes, on "A photoreal game demo..." (r/SideProject)
> 2. "One month og chili crunch..." (r/SideProject)
> 3. "My eSIM app makes 2x my SWE salary..." (r/SideProject)
> 4. [comment] Frosty-Telephone-747 on "What other jobs can I do with a Comp Science Degree?" (r/cscareerquestions)
> 5. "A photoreal game demo which can be accessed from browser" (r/SideProject) — same thread as #1
> 6. "org-draw is now available on MELPA!" (r/emacs)
> 7. "Legion - AI agents inside your Elixir app..." (r/elixir)
> 8. "How (and why) the Open Jobs project keeps ~3 million jobs..." (r/vibecoding)
> 9. "My side project read 9.2 million news articles in 145 days..." (r/SideProject)
> 10. "I made a little over $15,000 in the last 12 months..." (r/WeirdSideHustles)
> 11. [comment] tokentrillionaire's own reply, on "I built a handwriting notebook app where Claude writes back..." (r/ClaudeAI)
> 12. "Pi 5 running Qwen 35B to rule my car" (r/raspberry_pi)
> 13. "Indeed laid off my pregnant wife, so I built a job search competitor with Claude..." (r/ClaudeAI)
> 14. "I built a missed-call text-back for tradespeople..." (r/EntrepreneurRideAlong)
> 15. "Built a SaaS to $22K MRR with $0 paid marketing..." (r/EntrepreneurRideAlong)
>
> **Next item to scrape (#16 onward), in list order:** "Obsidian Appreciation
> Post" (r/ObsidianMD, ~20 days old at time of writing), then "Xero/QuickBooks
> bookkeeping might be one of the most underrated 'semi-passive' skills"
> (r/passive_income), then "Lemma - A language for business rules" (r/elixir).
> To resume: open `old.reddit.com/user/lovebes/saved/`, page forward (25/page)
> past the 15 titles above, and continue the click-through-to-post-page method
> from there. The dev DB was deliberately wiped and re-ingested clean partway
> through this session (see git-untracked scratchpad JSON files) — if picking
> this up much later, verify `saved_posts` still has exactly these 15 rows
> before continuing, in case of another wipe.

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
- ~~Reddit OAuth2~~ — removed, see update note above; saved posts and
  comments come from browser-driven scraping instead
- OpenRouter API for research-doc generation (model configurable via
  `OPENROUTER_MODEL` env var; currently `openai/gpt-4o-mini`)
- `earmark` for markdown→HTML rendering of generated research docs;
  Tailwind's `@tailwindcss/typography` plugin (`@plugin
  "@tailwindcss/typography";` in `app.css`) for `prose` styling

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

1. User pastes/edits the raw comment section in a textarea (prefilled from
   `post.comments_raw`) and sets "number of top comments to include" (no
   fixed default enforced by the system beyond a sane UI suggestion, e.g.
   20 — user can change it per post since thread quality/size varies)
2. Build a prompt containing: post title, post body/URL, subreddit, and the
   raw comment text, instructing the model to parse/prioritize the top N by
   position itself (Reddit's default sort puts higher-scored ones first)
3. Send to OpenRouter (configured model) with a prompt template instructing
   it to produce a clean, well-structured markdown research document
4. Write the result to `~/reddit-research/<slug>.md` with YAML frontmatter:
   `title`, `url`, `subreddit`, `date`, `tags` — this **overwrites** the
   same file on regeneration (slug is stable, keyed on post id)
5. Upsert (not insert) a `research_docs` row keyed on `saved_post_id`
   (unique index) — one row per post, so regenerating updates file_path/
   model/comment_count_used/generated_at in place rather than accumulating
   history rows
6. The show page reads the row + file back (`Research.latest_doc/1`,
   `Research.read_doc_content/1`) and renders it live in a card right below
   the generate form — converted markdown→HTML via `Earmark.as_html!/1`
   (frontmatter stripped first) into a `prose` (Tailwind typography plugin)
   block, so regenerating updates the on-page result immediately, no reload
7. The file path is a same-origin link (`GET /posts/:post_id/research_doc`,
   `ResearchDocController`, serves the raw file as `text/plain`) — **not** a
   `file://` URI, which Chrome blocks as a top-level navigation from an
   `http://` page
8. Model: `openai/gpt-4o-mini` (paid, ~$0.20 total for 100+ docs at this
   post/comment size) — free OpenRouter models were tried first
   (`nvidia/nemotron-3-ultra-550b-a55b:free`, `google/gemma-4-31b-it:free`)
   but hit shared-pool rate-limit/overload errors (502s, 429s) under normal
   use; that's inherent to every free-tier model on OpenRouter, not a
   specific-model problem, so switched to paid rather than chasing a
   more-reliable free one

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
