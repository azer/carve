defmodule Carve.LazyLinksTest do
  use ExUnit.Case, async: true

  defmodule TestUser do
    defstruct [:id, :name, :role, :team_id]
  end

  defmodule TestTeam do
    defstruct [:id, :name]
  end

  defmodule TestPost do
    defstruct [:id, :title, :author_id]
  end

  defmodule TestComment do
    defstruct [:id, :content, :user_id]
  end

  # Track function calls for both regular and lazy loading
  defmodule Posts do
    def get_by_user_id(user_id) do
      send(self(), {:posts_called, user_id})
      [
        %TestPost{id: user_id * 10, title: "Lazy Post 1", author_id: user_id},
        %TestPost{id: user_id * 10 + 1, title: "Lazy Post 2", author_id: user_id}
      ]
    end
  end

  defmodule Teams do
    def get_by_user_id(user_id) do
      send(self(), {:teams_called, user_id})
      [
        %TestTeam{id: user_id * 10, name: "Lazy Team 1"},
      ]
    end
  end

  defmodule Comments do
    def get_by_user_id(user_id) do
      send(self(), {:comments_called, user_id})
      [%TestComment{id: user_id * 100, content: "Lazy Comment", user_id: user_id}]
    end
  end

  # Regular post view
  defmodule PostJSON do
    use Carve.View, :post

    get fn id ->
      %TestPost{id: id, title: "Post #{id}", author_id: div(id, 10)}
    end

    view fn post ->
      %{
        id: hash(post.id),
        title: post.title,
        author_id: post.author_id
      }
    end
  end

  # Regular comment view
  defmodule CommentJSON do
    use Carve.View, :comment

    get fn id ->
      %TestComment{id: id, content: "Comment #{id}", user_id: div(id, 10)}
    end

    view fn comment ->
      %{
        id: hash(comment.id),
        content: comment.content,
        user_id: comment.user_id
      }
    end
  end


  # Regular comment view
  defmodule TeamJSON do
    use Carve.View, :team

    get fn id ->
      %TestTeam{id: id, name: "Team #{id}"}
    end

    view fn team ->
      %{
        id: hash(team.id),
        name: team.name
      }
    end
  end

  # Main test view with both regular and lazy links
  defmodule UserJSON do
    use Carve.View, :user

    view fn user ->
      %{
        id: hash(user.id),
        name: user.name,
        role: user.role,
	team_id: user.team_id
      }
    end

    links fn user ->
      %{
	TeamJSON => user.team_id,
        PostJSON => fn -> Posts.get_by_user_id(user.id) end,  # Lazy link
        CommentJSON => fn -> Comments.get_by_user_id(user.id) end # Lazy link
      }
    end
  end

  describe "lazy links behavior" do
    test "when include not specified, includes regular links only and no lazy functions called" do
      user = %TestUser{id: 1, name: "User", role: "user", team_id: 3}
      result = UserJSON.show(%{result: user})

      # Lazy links should not be called
      refute_received {:posts_called, 1}
      refute_received {:comments_called, 1}

      assert length(result.links) == 1
      assert Enum.count(result.links, & &1.type == :team) == 1
    end

    test "when include param empty, no links included and no functions called" do
      user = %TestUser{id: 1, name: "User", role: "user", team_id: 4}
      result = UserJSON.show(%{result: user, include: []})

      # No functions should be called
      refute_received {:posts_called, 1}
      refute_received {:comments_called, 1}

      assert result.links == []
    end

    test "lazy link function only called when its type explicitly included" do
      user = %TestUser{id: 1, name: "User", role: "user", team_id: 4}
      result = UserJSON.show(%{result: user, include: [:post]})

      # Only lazy posts should be called
      assert_received {:posts_called, 1}
      refute_received {:comments_called, 1}

      assert length(result.links) == 2  # Two posts
      assert Enum.all?(result.links, & &1.type == :post)
    end

    test "multiple types can be included selectively" do
      user = %TestUser{id: 1, name: "User", role: "user", team_id: 4}
      result = UserJSON.show(%{result: user, include: [:post, :comment]})

      # Check correct functions called
      assert_received {:posts_called, 1}
      assert_received {:comments_called, 1}

      # Check links in result
      assert length(result.links) == 3  # 2 lazy posts + 1 regular comment
      assert Enum.count(result.links, & &1.type == :post) == 2
      assert Enum.count(result.links, & &1.type == :comment) == 1
    end

    test "lazy loading works with index action" do
      users = [
        %TestUser{id: 1, name: "User 1", role: "user", team_id: 7},
        %TestUser{id: 2, name: "User 2", role: "user", team_id: 8}
      ]

      result = UserJSON.index(%{result: users, include: [:post]})

      assert_received {:posts_called, 1}
      assert_received {:posts_called, 2}
      refute_received {:comments_called, _}
      refute_received {:posts_called, _}
      refute_received {:comments_called, _}

      assert length(result.links) == 4
      assert Enum.all?(result.links, & &1.type == :post)
    end
  end
end
