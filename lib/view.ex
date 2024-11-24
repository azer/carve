defmodule Carve.View do
  @moduledoc """
  Carve.View provides a DSL for quickly building JSON API views in Phoenix applications.

  It automatically creates `show` and `index` functions for Phoenix controllers,
  handles ID hashing, and manages links between different entities.

  ## Usage

  In your Phoenix JSON view module:

      defmodule MyApp.UserJSON do
        use Carve.View, :user

        links fn user ->
          %{
            MyApp.TeamJSON => user.team_id,
            MyApp.ProfileJSON => user.profile_id
          }
        end

        get fn id ->
          MyApp.Users.get_by_id!(id)
        end

        view fn user ->
          %{
            id: hash(user.id),
            name: user.name,
            team_id: MyApp.TeamJSON.hash(user.team_id),
            profile_id: MyApp.ProfileJSON.hash(user.profile_id)
          }
        end
      end

  This will automatically create `show/1` and `index/1` functions that can be used
  in your Phoenix controllers, handling both data rendering and link generation.

  ## Generated Functions

  The `use Carve.View, :type` macro generates several functions at compile time:

  - `index/1`: Handles rendering a list of entities with their links.
  - `show/1`: Handles rendering a single entity with its links.
  - `hash/1`: Alias of encode_id.
  - `encode_id/1`: Encodes an ID using the view type as a salt.
  - `decode_id/1`: Decodes an ID using the view type as a salt.
  - `type_name/0`: Returns the type of the view.
  - `process_links/1`: Processes links for an entity (if `links` macro is used).

  Here's an example of what these functions might look like at runtime:

      def index(%{result: data}) when is_list(data) do
        results = Enum.map(data, &prepare_for_view/1)
        links = Carve.Links.get_links_by_data(__MODULE__, data)
        %{result: results, links: links}
      end

      def show(%{result: data}) do
        result = prepare_for_view(data)
        links = Carve.Links.get_links_by_data(__MODULE__, data)
        %{result: result, links: links}
      end

      def hash(id) when is_integer(id), do: Carve.HashIds.encode(:user, id)
      def hash(%{id: id}), do: hash(id)

      def type_name, do: :user

      def process_links(data) do
        %{
          MyApp.TeamJSON => data.team_id,
          MyApp.ProfileJSON => data.profile_id
        }
      end

  These generated functions work together to provide a seamless API for rendering
  JSON views with proper linking and ID hashing.
  """

  @doc """
  Sets up the view module with the given type.

  This macro is called when you use `use Carve.View, :type` in your module.
  It imports Carve.View functions and sets up the necessary module attributes.

  ## Parameters

  - `type`: An atom representing the type of the view (e.g., :user, :post).

  ## Example

      defmodule MyApp.UserJSON do
        use Carve.View, :user
        # ... rest of the module
      end
  """
  defmacro __using__(type) do
    quote do
      @carve_type unquote(type)
      import Carve.View
      @before_compile Carve.View
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    has_process_links = Module.defines?(env.module, {:process_links, 1})

    quote do
      def index(%{result: data, include: include}) when is_list(data) do
        results = Enum.map(data, &prepare_for_view/1)

        links =
          if unquote(has_process_links) do
            Carve.Links.get_links_by_data(__MODULE__, data, %{}, include)
          else
            []
          end

        %{
          result: results,
          links: links
        }
      end

      # Without include - include everything
      def index(%{result: data}) when is_list(data) do
        results = Enum.map(data, &prepare_for_view/1)

        links =
          if unquote(has_process_links) do
            # Pass nil to include all
            Carve.Links.get_links_by_data(__MODULE__, data, %{}, nil)
          else
            []
          end

        %{
          result: results,
          links: links
        }
      end

      # With include parameter - use whitelist
      def show(%{result: data, include: include}) do
        result = prepare_for_view(data)

        links =
          if unquote(has_process_links) do
            Carve.Links.get_links_by_data(__MODULE__, data, %{}, include)
          else
            []
          end

        %{
          result: result,
          links: links
        }
      end

      # Without include - include everything
      def show(%{result: data}) do
        result = prepare_for_view(data)

        links =
          if unquote(has_process_links) do
            # Pass nil to include all
            Carve.Links.get_links_by_data(__MODULE__, data, %{}, nil)
          else
            []
          end

        %{
          result: result,
          links: links
        }
      end

      # Hash an integer ID
      def hash(id) when is_integer(id) do
        Carve.HashIds.encode(@carve_type, id)
      end

      # Hash an entity with an ID
      def hash(%{id: id}) do
        hash(id)
      end

      # Hash an integer ID
      def encode_id(id) when is_integer(id) do
        Carve.HashIds.encode(@carve_type, id)
      end

      # Decode a hashed ID
      def decode_id(hashed_id) when is_binary(hashed_id) do
        case Carve.HashIds.decode(@carve_type, hashed_id) do
          {:ok, id} -> {:ok, id}
          {:error, reason} -> {:error, reason}
        end
      end

      # Return the type of this view
      def type_name, do: @carve_type

      # Default process_links function if not defined by user
      unless unquote(has_process_links) do
        def process_links(_), do: %{}
      end
    end
  end

  @doc """
  Defines the links for the current view.

  This macro allows you to specify how to generate links for the current entity.

  ## Parameters

  - `func`: A function that takes the entity data and returns a map of links.

  ## Example

      links fn user ->
        %{
          MyApp.TeamJSON => user.team_id,
          MyApp.ProfileJSON => user.profile_id
        }
      end
  """
  defmacro links(func) do
    quote do
      def process_links(data) do
        unquote(func).(data)
      end
    end
  end

  @doc """
  Defines how to render the view for the current entity.

  This macro specifies how to format the entity data for JSON output.

  ## Parameters

  - `func`: A function that takes the entity data and returns a map for JSON rendering.

  ## Example

      view fn user ->
        %{
          id: hash(user.id),
          name: user.name,
          team_id: MyApp.TeamJSON.hash(user.team_id)
        }
      end
  """
  defmacro view(func) do
    quote do
      def prepare_for_view(data) do
        view = unquote(func).(data)

        %{
          id: hash(data.id),
          type: type_name(),
          data: view
        }
      end
    end
  end

  @doc """
  Defines how to retrieve an entity by its ID.

  This macro specifies a function to fetch an entity given its ID.

  ## Parameters

  - `func`: A function that takes an ID and returns the corresponding entity.

  ## Example

      get fn id ->
        MyApp.Users.get_by_id!(id)
      end
  """
  defmacro get(func) do
    quote do
      def get_by_id(id) do
        unquote(func).(id)
      end
    end
  end
end
