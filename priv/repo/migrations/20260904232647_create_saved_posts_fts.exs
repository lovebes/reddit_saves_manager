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
