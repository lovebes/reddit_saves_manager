defmodule RedditSavesManager.Research do
  alias RedditSavesManager.Repo
  alias RedditSavesManager.Research.{Doc, OpenRouterClient}

  @doc """
  Builds the research-doc prompt from a post and its raw, unstructured comment
  text (a straight copy-paste off the permalink page — author names, bodies,
  and reply nesting all jumbled together, not parsed into fields; vote scores
  aren't part of the copyable page text at all, so they're never in here).
  The model is instructed to do that parsing/cleanup itself as part of writing
  the doc, rather than this code sorting comments by a structured score first.
  """
  def build_prompt(post, comments_raw, comment_count) do
    """
    You are producing a clean, well-structured markdown research document from a Reddit thread.

    Post title: #{post.title}
    Subreddit: r/#{post.subreddit}
    URL: #{post.url}

    Post body:
    #{post.selftext}

    Raw comment section (unstructured — copied straight off the page, so it
    includes author names, comment bodies, and UI noise like "Reply"/"Share"
    all mixed together; figure out the structure yourself). Comments appear in
    Reddit's default "Best" sort order, so earlier ones in this text are
    generally higher-scored than later ones — there are no explicit vote
    numbers in this copy:
    #{comments_raw}

    Write a markdown document that summarizes the key insights, points of debate, and
    actionable takeaways from this thread. Focus mainly on roughly the top #{comment_count}
    comments by that position in the sort order, treating later ones as
    lower-priority supporting context. Use headers and bullet points. Synthesize
    the comments rather than repeating them verbatim.
    """
  end

  @doc """
  Generates and saves a research doc from a post and its raw comment-section text.

  `comments_raw` is supplied by the caller (a browser scrape/copy-paste pulls
  it — Reddit's API denies the OAuth scopes this app would need), not fetched
  here, and is not parsed into structured fields; the model does that.
  """
  def generate_and_save(post, comments_raw, comment_count) do
    with prompt <- build_prompt(post, comments_raw, comment_count),
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
