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
    dir =
      Application.get_env(
        :reddit_saves_manager,
        :research_output_dir,
        Path.expand("~/reddit-research")
      )

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
