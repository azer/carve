defmodule Carve.LinksTest do
  use ExUnit.Case, async: true
  alias Carve.Links

  defmodule UserJSON do
    use Carve.View, :user

    get fn id ->
      case id do
	nil -> nil
	_ -> %{id: id, name: "User #{id}", email: "user#{id}@example.com"}
      end
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
        Carve.LinksTest.PostJSON => Carve.LinksTest.PostJSON.get_posts_by_user_id(user.id)
      }
    end
  end

  defmodule PostJSON do
    use Carve.View, :post

    get fn id ->
      user_id = div(id, 1000) + 1
      %{id: id, title: "Post #{id}", content: "Content of post #{id}", user_id: user_id, tag_ids: [id * 2, id * 2 + 1]}
    end

    view fn post ->
      %{
        id: hash(post.id),
        title: post.title,
        content: post.content,
        user_id: Carve.LinksTest.UserJSON.hash(post.user_id),
        tag_ids: Enum.map(post.tag_ids, &Carve.LinksTest.TagJSON.hash/1)
      }
    end

    links fn post ->
      %{
        Carve.LinksTest.UserJSON => post.user_id,
        Carve.LinksTest.CommentJSON => get_comments_by_post_id(post.id),
        Carve.LinksTest.TagJSON => post.tag_ids
      }
    end

    # Updated helper functions
    def get_posts_by_user_id(user_id) do
      [user_id * 1000 + 1, user_id * 1000 + 2, user_id * 1000 + 3]
    end

    def get_comments_by_post_id(post_id) do
      [post_id * 100 + 1, post_id * 100 + 2]
    end
  end

  defmodule CommentJSON do
    use Carve.View, :comment

    get fn id ->
      post_id = div(id, 100)
      user_id = rem(id, 100) + 1
      %{id: id, content: "Comment #{id}", post_id: post_id, user_id: user_id}
    end

    view fn comment ->
      %{
        id: hash(comment.id),
        content: comment.content,
        post_id: Carve.LinksTest.PostJSON.hash(comment.post_id),
        user_id: Carve.LinksTest.UserJSON.hash(comment.user_id)
      }
    end

    links fn comment ->
      %{
        Carve.LinksTest.PostJSON => comment.post_id,
        Carve.LinksTest.UserJSON => comment.user_id
      }
    end
  end

  defmodule TagJSON do
    use Carve.View, :tag

    get fn id ->
      %{id: id, name: "Tag #{id}"}
    end

    view fn tag ->
      %{
        id: hash(tag.id),
        name: tag.name
      }
    end

    links fn tag ->
      %{
        Carve.LinksTest.PostJSON => get_posts_by_tag_id(tag.id)
      }
    end

    # Updated helper function
    def get_posts_by_tag_id(tag_id) do
      [tag_id * 1000 + 1, tag_id * 1000 + 2]
    end
  end

  defmodule ArbitraryKeyJSON do
    use Carve.View, :arbitrary_key

    get fn {key, value} ->
      %{key => value}
    end

    view fn data ->
      data
    end

    links fn _data ->
      %{
        Carve.LinksTest.UserJSON => 1  # Always link to user 1 for simplicity
      }
    end
  end

  test "get_links_by_id returns correct links for a user" do
    links = Links.get_links_by_id(UserJSON, 1)

    assert length(links) == 3
    assert Enum.all?(links, fn link -> link.type == :post end)
    assert Enum.map(links, & &1.id) == Enum.map([1001, 1002, 1003], &PostJSON.hash/1)
  end

  test "get_links_by_data returns correct links for a post" do
    post_data = %{id: 1001, title: "Post 1001", content: "Content of post 1001", user_id: 1, tag_ids: [2002, 2003]}
    links = Links.get_links_by_data(PostJSON, post_data)

    assert length(links) == 5  # 1 user + 2 comments + 2 tags
    assert Enum.count(links, & &1.type == :user) == 1
    assert Enum.count(links, & &1.type == :comment) == 2
    assert Enum.count(links, & &1.type == :tag) == 2
  end

  test "get_links_by_id handles circular references without infinite loops" do
    links = Links.get_links_by_id(CommentJSON, 100101)

    assert length(links) == 2
    assert Enum.any?(links, & &1.type == :post)
    assert Enum.any?(links, & &1.type == :user)
  end

  test "get_links_by_id returns empty list for nil id" do
    assert Links.get_links_by_id(UserJSON, nil) == []
  end

  test "get_links_by_data returns empty list for nil data" do
    assert Links.get_links_by_data(UserJSON, nil) == []
  end

  test "get_links_by_data returns empty list for non-map data" do
    assert Links.get_links_by_data(UserJSON, "Not a map") == []
  end

  test "get_links_by_id handles a list of IDs" do
    links = Links.get_links_by_id(TagJSON, [1, 2, 3])

    assert length(links) == 6  # 2 posts per tag
    assert Enum.all?(links, & &1.type == :post)
  end

  test "get_links_by_data handles a list of data items" do
    post_data_list = [
      %{id: 1001, title: "Post 1001", content: "Content 1", user_id: 1, tag_ids: [2002, 2003]},
      %{id: 1002, title: "Post 1002", content: "Content 2", user_id: 1, tag_ids: [2004, 2005]}
    ]

    links = Links.get_links_by_data(PostJSON, post_data_list)

    assert length(links) == 9  # (1 user + 2 comments + 2 tags) * 2 posts - 1 duplicate user
    assert Enum.count(links, & &1.type == :user) == 1
    assert Enum.count(links, & &1.type == :comment) == 4
    assert Enum.count(links, & &1.type == :tag) == 4
  end

  test "get_links_by_id handles non-existent IDs gracefully" do
    links = Links.get_links_by_id(UserJSON, nil)
    assert links == []
  end

    test "get_links_by_data handles maps with arbitrary keys" do
    arbitrary_key = "foo"
    arbitrary_key_data = %{arbitrary_key => "bar"}
    links = Links.get_links_by_data(ArbitraryKeyJSON, arbitrary_key_data)

    assert length(links) == 1
    assert Enum.at(links, 0).type == :user
    assert Enum.at(links, 0).id == UserJSON.hash(1)
  end

  test "get_links_by_id handles arbitrary key-value pair IDs" do
    arbitrary_key = "foo"
    links = Links.get_links_by_id(ArbitraryKeyJSON, {arbitrary_key, "bar"})

    assert length(links) == 1
    assert Enum.at(links, 0).type == :user
    assert Enum.at(links, 0).id == UserJSON.hash(1)
    end

  test "get_links_by_id with whitelist returns only whitelisted links" do
    links = Links.get_links_by_id(UserJSON, 1, %{}, [:post])

    assert length(links) == 3
    assert Enum.all?(links, fn link -> link.type == :post end)
  end

  test "get_links_by_data with whitelist returns only whitelisted links" do
    post_data = %{id: 1001, title: "Post 1001", content: "Content of post 1001", user_id: 1, tag_ids: [2002, 2003]}
    links = Links.get_links_by_data(PostJSON, post_data, %{}, [:user, :comment])

    assert length(links) == 3  # 1 user + 2 comments (tags filtered out)
    assert Enum.count(links, & &1.type == :user) == 1
    assert Enum.count(links, & &1.type == :comment) == 2
    refute Enum.any?(links, & &1.type == :tag)
  end

  test "get_links_by_id with empty whitelist returns no links" do
    links = Links.get_links_by_id(UserJSON, 1, %{}, [])

    assert links == []
  end

  test "get_links_by_data with empty whitelist returns no links" do
    post_data = %{id: 1001, title: "Post 1001", content: "Content of post 1001", user_id: 1, tag_ids: [2002, 2003]}
    links = Links.get_links_by_data(PostJSON, post_data, %{}, [])

    assert links == []
  end

  test "get_links_by_data handles a list of data items with whitelist" do
    post_data_list = [
      %{id: 1001, title: "Post 1001", content: "Content 1", user_id: 1, tag_ids: [2002, 2003]},
      %{id: 1002, title: "Post 1002", content: "Content 2", user_id: 1, tag_ids: [2004, 2005]}
    ]

    links = Links.get_links_by_data(PostJSON, post_data_list, %{}, [:user, :comment])

    assert length(links) == 5  # (1 user + 2 comments) * 2 posts - 1 duplicate user
    assert Enum.count(links, & &1.type == :user) == 1
    assert Enum.count(links, & &1.type == :comment) == 4
    refute Enum.any?(links, & &1.type == :tag)
  end


end
