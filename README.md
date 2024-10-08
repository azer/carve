# Carve

DSL for building JSON APIs fast. Creates endpoint views, renders linked data automatically.

Features:

* Rendering structured JSON views automatically
* Retrieving links between different data types
* Creating index/show methods for views
* Hashing IDs with unique & short strings (e.g `123` -> `Xk9Lp2R`)

Here's how an endpoint view generated by Carve looks like:

```js
{
  "result": {
    "id": "D3Wcorr0oa",
    "type": "user",
    "data": { ... }
  },
  "links": [
    {
      "id": "Xk9Lp2Rr4m",
      "type": "team",
      "data": { ... }
    },
    {
      "id": "Bz7Jt5Yq1n",
      "type": "profile",
      "data": { ... }
    }
  ]
}
```

## Installation

Add `carve` to your list of dependencies in `mix.exs`:


```elixir
def deps do
  [
    {:carve, "~> 0.1.0"}
  ]
end
```


To configure custom hashing salt, add to `config.exs`:

```elixir
config :carve,
  salt: "your-secret-salt",
  min_length: 10
```

## Usage

In your Phoenix JSON view, just declare how your endpoint should look like:

```elixir
defmodule UserJSON do
    use Carve.View, :user

    view fn user ->
      %{
        id: hash(user.id), # provided by Carve.View, encodes numerical ID (123) with an entity-specific salt (D3Wcorr0oa).
        name: user.name
      }
    end
end
```

And that's it -- this macro will make `index(%{ result: users })` and `show(%{ result: user })` methods available for your controller.

Of course, just formatting the view alone is not Carvers only point; you can declare the links of each view, and Carve will automatically output them for the client:

```elixir
defmodule UserJSON do
    use Carve.View, :user

    # Return the links of a given user as ViewModule => id
    links fn user ->
        %{
            FooWeb.TeamJSON => user.team_id, # You can also pass list of ids or the Ecto record(s)
            FooWeb. ProfileJSON => user.profile_id
        }
    end

    # Provide a method to retrieve user by id. This will be used by Carve to render links automatically.
    get fn id ->
        Foo.Users.get_by_id!(id)
    end

    view fn user ->
      %{
        id: hash(user.id),
        team_id: FooWeb.TeamJSON.hash(user.team_id),
        profile_id: FooWeb.ProfileJSON.hash(user.profile_id),
        name: user.name
      }
    end
end
```

After activating `show` and `index` methods in the controller:

```elixir
render(conn, :index, result: requests) # or render(conn, :show, result: record)
```

Example response Carve will render for this view:

```json
{
  "result": {
    "id": "D3Wcorr0oa",
    "type": "user",
    "data": {
      "id": "D3Wcorr0oa",
      "name": "John Doe",
      "team_id": "Xk9Lp2Rr4m",
      "profile_id": "Bz7Jt5Yq1n"
    }
  },
  "links": [
    {
      "id": "Xk9Lp2Rr4m",
      "type": "team",
      "data": {
        "id": "Xk9Lp2Rr4m",
        "name": "Engineering Team",
        "description": "Our awesome engineering team"
      }
    },
    {
      "id": "Bz7Jt5Yq1n",
      "type": "profile",
      "data": {
        "id": "Bz7Jt5Yq1n",
        "bio": "Software engineer passionate about Elixir",
        "avatar_url": "https://example.com/avatars/johndoe.jpg"
      }
    }
  ]
}
```

### Example Controller

Carve provides a flexible way to control which linked data is included in the response. This is achieved through the include parameter. Here's an example of how to use Carve in your Phoenix controllers:

```elixir
defmodule UserController do
  use FooWeb, :controller

  def show(conn, %{"id" => id} = params) do
    user = Foo.Users.get_user!(id)
    include = Carve.fetch_include(params)

    render(conn, :show, %{ result: user, include: include })
  end

  def index(conn, params) do
    users = Foo.Users.list_users()
    include = Carve.fetch_include(params)

    render(conn, :index, %{ result: users, include: include })
  end
end
```

This example also shows reading & parsing the `include` parameter, which can be one of following:

* Not specified (`GET  /api/users`): All link types are included.
* Empty list (`GET /api/users?included=`): No link types are included.
* Custom types: (`GET /api/users/123?include=team,profile`): Include comma-separated link types only.

## How does it work?

* Carve macros create view functions `index(%{ result: users })` and `show(%{ result: user })`
* Controller calls these view functions
* Carve pulls the list of links for given data (list or single record)
* Carve calls the `get_by_id` (`get` macro expanded) and `prepare_for_view` (`view` macro expanded) functions for each link
* The final expanded list of links get flattened & cleaned, returned to user with the main result: `{ result: {} || [], links: [] }`

## API

More detailed API docs are available at [https://hexdocs.pm/carve/Carve.html](https://hexdocs.pm/carve/Carve.html)
