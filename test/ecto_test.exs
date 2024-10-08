 defmodule Carve.EctoWorkspace do
    use Ecto.Schema

    schema "workspaces" do
      field :name, :string
      belongs_to :user, Carve.EctoUser
    end
end

# Define Ecto schemas outside the test module
defmodule Carve.EctoUser do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    has_many :posts, Carve.EctoPost
  end
end

defmodule Carve.EctoPost do
  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :content, :string
    belongs_to :user, Carve.EctoUser
    has_many :comments, Carve.EctoComment
    many_to_many :tags, Carve.EctoTag, join_through: "posts_tags"
  end
end

defmodule Carve.EctoComment do
  use Ecto.Schema

  schema "comments" do
    field :content, :string
    belongs_to :post, Carve.EctoPost
    belongs_to :user, Carve.EctoUser
  end
end

defmodule Carve.EctoTag do
  use Ecto.Schema

  schema "tags" do
    field :name, :string
    many_to_many :posts, Carve.EctoPost, join_through: "posts_tags"
  end
end

defmodule Carve.EctoLinksTest do
  use ExUnit.Case, async: true
  alias Carve.Links

   defmodule EctoUserJSON do
    use Carve.View, :ecto_user

    get fn id ->
      %Carve.EctoUser{id: id, name: "User #{id}", email: "user#{id}@example.com"}
    end

    view fn user ->
      %{
        id: hash(user.id),
        name: user.name,
        email: user.email
      }
    end

    links fn user ->
      %{
        Carve.EctoLinksTest.EctoPostJSON => get_post_ids_for_user(user.id),
        Carve.EctoLinksTest.WorkspaceJSON => get_workspaces_for_user(user.id)
      }
    end

    # Helper functions
    defp get_post_ids_for_user(user_id) do
      [user_id * 10, user_id * 10 + 1, user_id * 10 + 2]
    end

    defp get_workspaces_for_user(user_id) do
      [
        %Carve.EctoWorkspace{id: user_id * 100 + 1, name: "Workspace 1 for User #{user_id}"},
        %Carve.EctoWorkspace{id: user_id * 100 + 2, name: "Workspace 2 for User #{user_id}"}
      ]
    end
  end

  defmodule EctoPostJSON do
    use Carve.View, :ecto_post

    get fn id ->
      %Carve.EctoPost{id: id, title: "Post #{id}", content: "Content of post #{id}", user_id: div(id, 10)}
    end

    view fn post ->
      %{
        id: hash(post.id),
        title: post.title,
        content: post.content,
        user_id: Carve.EctoLinksTest.EctoUserJSON.hash(post.user_id)
      }
    end

    links fn post ->
      %{
        Carve.EctoLinksTest.EctoUserJSON => post.user_id,
        Carve.EctoLinksTest.EctoCommentJSON => Carve.if_loaded(post.comments) || get_comment_ids_for_post(post.id),
        Carve.EctoLinksTest.EctoTagJSON => Carve.if_loaded(post.tags) || get_tag_ids_for_post(post.id)
      }
    end

    # Helper functions
    defp get_comment_ids_for_post(post_id) do
      [post_id * 100, post_id * 100 + 1]
    end

    defp get_tag_ids_for_post(post_id) do
      [post_id * 10, post_id * 10 + 1]
    end
  end

  defmodule EctoCommentJSON do
    use Carve.View, :ecto_comment

    get fn id ->
      %Carve.EctoComment{id: id, content: "Comment #{id}", post_id: div(id, 100), user_id: rem(id, 100) + 1}
    end

    view fn comment ->
      %{
        id: hash(comment.id),
        content: comment.content,
        post_id: Carve.EctoLinksTest.EctoPostJSON.hash(comment.post_id),
        user_id: Carve.EctoLinksTest.EctoUserJSON.hash(comment.user_id)
      }
    end

    links fn comment ->
      %{
        Carve.EctoLinksTest.EctoPostJSON => comment.post_id,
        Carve.EctoLinksTest.EctoUserJSON => comment.user_id
      }
    end
  end

  defmodule EctoTagJSON do
    use Carve.View, :ecto_tag

    get fn id ->
      %Carve.EctoTag{id: id, name: "Tag #{id}"}
    end

    view fn tag ->
      %{
        id: hash(tag.id),
        name: tag.name
      }
    end

    links fn tag ->
      %{
        Carve.EctoLinksTest.EctoPostJSON => get_post_ids_for_tag(tag.id)
      }
    end

    # Helper function
    defp get_post_ids_for_tag(tag_id) do
      [tag_id * 10, tag_id * 10 + 1]
    end
  end

  defmodule WorkspaceJSON do
    use Carve.View, :ecto_workspace

    get fn id ->
      %Carve.EctoWorkspace{id: id, name: "Workspace #{id}"}
    end

    view fn workspace ->
      %{
        id: hash(workspace.id),
        name: workspace.name
      }
    end

    links fn _workspace ->
      %{}  # No links for simplicity
    end
  end

  test "get_links_by_data handles Ecto schema structs" do
    ecto_post = %Carve.EctoPost{
      id: 1001,
      title: "Ecto Post 1001",
      content: "Content of Ecto post 1001",
      user_id: 1,
      user: %Carve.EctoUser{id: 1, name: "Ecto User 1", email: "ecto_user1@example.com"},
      comments: [
        %Carve.EctoComment{id: 100101, content: "Ecto Comment 1", post_id: 1001, user_id: 2},
        %Carve.EctoComment{id: 100102, content: "Ecto Comment 2", post_id: 1001, user_id: 3}
      ],
      tags: [
        %Carve.EctoTag{id: 1, name: "Ecto Tag 1"},
        %Carve.EctoTag{id: 2, name: "Ecto Tag 2"}
      ]
    }

    links = Links.get_links_by_data(EctoPostJSON, ecto_post)

    assert length(links) == 5  # 1 user + 2 comments + 2 tags
    assert Enum.count(links, & &1.type == :ecto_user) == 1
    assert Enum.count(links, & &1.type == :ecto_comment) == 2
    assert Enum.count(links, & &1.type == :ecto_tag) == 2
  end

  test "get_links_by_id handles Ecto schema ID" do
    links = Links.get_links_by_id(EctoPostJSON, 1001)

    # We expect:
    # 1 user link
    # 2 comment links (based on get_comment_ids_for_post/1)
    # 2 tag links (based on get_tag_ids_for_post/1)
    assert length(links) == 5

    assert Enum.count(links, & &1.type == :ecto_user) == 1
    assert Enum.count(links, & &1.type == :ecto_comment) == 2
    assert Enum.count(links, & &1.type == :ecto_tag) == 2

    # Check user link
    user_link = Enum.find(links, & &1.type == :ecto_user)
    assert user_link.id == EctoUserJSON.hash(100)

    # Check comment links
    comment_links = Enum.filter(links, & &1.type == :ecto_comment)
    assert Enum.map(comment_links, & &1.id) == [
      EctoCommentJSON.hash(100100),
      EctoCommentJSON.hash(100101)
    ]

    # Check tag links
    tag_links = Enum.filter(links, & &1.type == :ecto_tag)
    assert Enum.map(tag_links, & &1.id) == [
      EctoTagJSON.hash(10010),
      EctoTagJSON.hash(10011)
    ]
  end

  # test "get_links_by_data handles list of Ecto schema structs" do
  #   ecto_posts = [
  #     %Carve.EctoPost{
  #       id: 1001,
  #       title: "Ecto Post 1001",
  #       content: "Content of Ecto post 1001",
  #       user_id: 1,
  #       comments: [%Carve.EctoComment{id: 100101, content: "Ecto Comment 1", user_id: 2}],
  #       tags: [%Carve.EctoTag{id: 1, name: "Ecto Tag 1"}]
  #     },
  #     %Carve.EctoPost{
  #       id: 1002,
  #       title: "Ecto Post 1002",
  #       content: "Content of Ecto post 1002",
  #       user_id: 1,
  #       comments: [%Carve.EctoComment{id: 100201, content: "Ecto Comment 2", user_id: 3}],
  #       tags: [%Carve.EctoTag{id: 2, name: "Ecto Tag 2"}]
  #     }
  #   ]

  #   links = Links.get_links_by_data(EctoPostJSON, ecto_posts)

  #   assert length(links) == 5  # 1 user + 2 comments + 2 tags + 2 posts
  #   assert Enum.count(links, & &1.type == :ecto_user) == 1
  #   assert Enum.count(links, & &1.type == :ecto_comment) == 2
  #   assert Enum.count(links, & &1.type == :ecto_tag) == 2
  # end

   test "get_links_by_data handles links returning actual data" do
    ecto_user = %Carve.EctoUser{
      id: 1,
      name: "Test User",
      email: "test@example.com"
    }

    links = Links.get_links_by_data(EctoUserJSON, ecto_user)

    assert length(links) == 5  # 3 posts + 2 workspaces
    assert Enum.count(links, & &1.type == :ecto_post) == 3
    assert Enum.count(links, & &1.type == :ecto_workspace) == 2

    post_ids = links
               |> Enum.filter(& &1.type == :ecto_post)
    |> Enum.map(& &1.id)

    assert post_ids == [
      Carve.EctoLinksTest.EctoPostJSON.hash(10),
      Carve.EctoLinksTest.EctoPostJSON.hash(11),
      Carve.EctoLinksTest.EctoPostJSON.hash(12)
    ]

    workspace_ids = links
                    |> Enum.filter(& &1.type == :ecto_workspace)
                    |> Enum.map(& &1.id)
    assert workspace_ids == [
      Carve.EctoLinksTest.WorkspaceJSON.hash(101),
      Carve.EctoLinksTest.WorkspaceJSON.hash(102)
    ]

    workspace_names = links
                      |> Enum.filter(& &1.type == :ecto_workspace)
                      |> Enum.map(& &1.data.name)
    assert workspace_names == [
      "Workspace 1 for User 1",
      "Workspace 2 for User 1"
    ]
  end
end
