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
