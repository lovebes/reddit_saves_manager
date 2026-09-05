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

  # Max length of the title-derived portion of the slug, before the
  # `-#{post.id}` uniqueness suffix is appended. Keeps the final filename
  # well clear of ENAMETOOLONG even for Reddit's up-to-300-character titles.
  @max_slug_length 80

  defp write_doc_file(post, markdown) do
    dir =
      Application.get_env(
        :reddit_saves_manager,
        :research_output_dir,
        Path.expand("~/reddit-research")
      )

    with :ok <- File.mkdir_p(dir) do
      file_path = Path.join(dir, "#{slug_for(post)}.md")

      frontmatter = """
      ---
      title: "#{post.title}"
      url: "#{post.url}"
      subreddit: "#{post.subreddit}"
      date: "#{Date.utc_today()}"
      tags: []
      ---

      """

      case File.write(file_path, frontmatter <> markdown) do
        :ok -> {:ok, file_path}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # Slugs are always suffixed with the post id for uniqueness (two posts with
  # the same or similarly-normalized title would otherwise silently overwrite
  # each other), and fall back to "post-#{id}" when the title has no ASCII
  # alphanumeric characters at all (e.g. an all-Korean title), which would
  # otherwise normalize to "" and produce a hidden dotfile path.
  defp slug_for(post) do
    base =
      post.title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    base =
      case base do
        "" -> "post"
        _ -> String.slice(base, 0, @max_slug_length) |> String.trim_trailing("-")
      end

    "#{base}-#{post.id}"
  end
end
