defmodule Carve.Links do
  @moduledoc """
  Carve.Links provides functionality for retrieving and processing links between different entities.

  This module is responsible for:
  - Fetching links for entities based on their IDs or data structures
  - Handling circular references and preventing infinite loops
  - Normalizing and preparing the final result set of links

  It works in conjunction with the view modules created using Carve.View to generate
  a complete set of links for any given entity or set of entities.
  """

  require Logger

  @doc """
  Retrieves links for a given module and ID or list of IDs.

  This function handles single IDs, lists of IDs, and prevents circular references
  using a visited map. It also supports filtering links based on a whitelist.

  ## Parameters

  - `module`: The module to use for fetching and processing links
  - `id`: A single ID or a list of IDs
  - `visited`: A map to keep track of visited entities (default: %{})
  - `whitelist`: An optional list of allowed link types (default: nil)

  ## Returns

  A list of prepared link maps.

  ## Examples

  iex> Carve.Links.get_links_by_id(UserJSON, 1)
  [%{type: :team, id: "abc123", data: %{...}}, %{type: :profile, id: "def456", data: %{...}}]

  iex> Carve.Links.get_links_by_id(UserJSON, [1, 2, 3], %{}, [:team])
  [%{type: :team, id: "abc123", data: %{...}}]
  """
  def get_links_by_id(module, id, visited \\ %{}, whitelist \\ nil)
  def get_links_by_id(_module, nil, _visited, _whitelist), do: []

  def get_links_by_id(module, id, visited, whitelist) when not is_list(id) do
    case Map.get(visited, {module, id}) do
      nil ->
        case module.get_by_id(id) do
          nil -> []
          data -> get_links_by_data(module, data, visited, whitelist) |> prepare_result(whitelist)
        end

      _ ->
        []
    end
  end

  def get_links_by_id(module, ids, visited, whitelist) when is_list(ids) do
    Enum.flat_map(ids, &get_links_by_id(module, &1, visited, whitelist))
    |> prepare_result(whitelist)
  end

  @doc """
  Retrieves links for a given module and data or list of data.

  This function handles single data structures, lists of data structures, and
  prevents circular references using a visited map. It also supports filtering links based on a whitelist.

  ## Parameters

  - `module`: The module to use for fetching and processing links
  - `data`: A single data structure or a list of data structures
  - `visited`: A map to keep track of visited entities (default: %{})
  - `whitelist`: An optional list of allowed link types (default: nil)

  ## Returns

  A list of prepared link maps.

  ## Examples

  iex> user = %{id: 1, name: "John Doe", team_id: 2}
  iex> Carve.Links.get_links_by_data(UserJSON, user)
  [%{type: :team, id: "abc123", data: %{...}}, %{type: :profile, id: "def456", data: %{...}}]

  iex> user = %{id: 1, name: "John Doe", team_id: 2}
  iex> Carve.Links.get_links_by_data(UserJSON, user, %{}, [:team])
  [%{type: :team, id: "abc123", data: %{...}}]
  """

  # Get links for an entity by its data, with support for collections and filtering
  def get_links_by_data(module, data, visited \\ %{}, whitelist \\ nil)

  # Return empty list for nil data
  def get_links_by_data(_module, nil, _visited, _whitelist), do: []

  # Handle collections by mapping over each item
  def get_links_by_data(module, data_list, visited, whitelist) when is_list(data_list) do
    Enum.flat_map(data_list, &get_links_by_data(module, &1, visited, whitelist))
    |> prepare_result(whitelist)
  end

  # Return empty list for non-map data
  def get_links_by_data(_module, data, _visited, _whitelist) when not is_map(data), do: []

  # Process single entity's links, with circular reference prevention
  def get_links_by_data(module, data, visited, whitelist) when not is_list(data) do
    case fetch_id(data) do
      {:ok, id} ->
        if Map.get(visited, {module, id}) do
          []
        else
          # Mark as visited and process links
          visited = Map.put(visited, {module, id}, true)

          # Get raw links and apply whitelist filtering/evaluation
          links =
            module.process_links(data)
            |> filter_and_evaluate_links(whitelist)

          links =
            links
            |> Enum.flat_map(fn {link_module, link_ids} ->
              link_ids
              |> normalize_link_ids()
              |> Enum.map(fn link_id ->
                process_single_link(link_module, link_id, visited)
              end)
          end)

          prepare_result(links, whitelist)
        end

      :error ->
        []
    end
  end

  defp filter_and_evaluate_links(links, nil) do
    # Without whitelist - evaluate regular links only (no lazy)
    links
    |> Enum.filter(fn {_, value} -> not is_function(value) end)
    |> Enum.into(%{})
  end

  defp filter_and_evaluate_links(_links, []) do
    # Empty whitelist - evaluate nothing
    %{}
  end

  defp filter_and_evaluate_links(links, whitelist) when is_list(whitelist) do
    links
    |> Enum.filter(fn {module, _} -> module.type_name() in whitelist end)
    |> Enum.map(fn {module, value} ->
      evaluated =
        case value do
          fun when is_function(fun, 0) -> fun.()
          other -> other
        end

      {module, evaluated}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Filters links based on the provided whitelist.

  ## Parameters

  - `links`: A map of links where keys are modules and values are IDs or lists of IDs
  - `whitelist`: A list of allowed link types (atoms)

  ## Returns

  A filtered map of links.

  ## Examples

  iex> links = %{UserJSON => [1, 2], PostJSON => [3, 4]}
  iex> Carve.Links.filter_links(links, [:user])
  %{UserJSON => [1, 2]}
  """
  defp filter_links(links, nil), do: links

  defp filter_links(links, whitelist) do
    links
    |> Enum.filter(fn {module, _} -> module.type_name() in whitelist end)
    |> Enum.into(%{})
  end

  @doc """
  Prepares the final result set by flattening, removing nil values, eliminating duplicates,
  and applying the whitelist filter if provided.

  ## Parameters

  - `result`: A list of link maps
  - `whitelist`: An optional list of allowed link types

  ## Returns

  A cleaned, uniquified, and optionally filtered list of link maps.

  ## Examples

  iex> result = [[%{type: :team, id: "abc"}, nil], [%{type: :profile, id: "def"}], %{type: :team, id: "abc"}]
  iex> Carve.Links.prepare_result(result, [:team])
  [%{type: :team, id: "abc"}]
  """
  def prepare_result(result, whitelist \\ nil) do
    result
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn %{type: type, id: id} -> {type, id} end)
    |> filter_result(whitelist)
  end

  defp filter_result(result, []), do: []
  defp filter_result(result, nil), do: result

  defp filter_result(result, whitelist) do
    Enum.filter(result, fn %{type: type} -> type in whitelist end)
  end

  @doc """
  Processes a single link, fetching its data and preparing it for output.

  This function handles both ID-based and data-based links, preventing circular
  references using the visited map.

  ## Parameters

  - `module`: The module to use for fetching and processing the link
  - `id_or_data`: Either an ID or a data structure representing the linked entity
  - `visited`: A map to keep track of visited entities

  ## Returns

  A prepared link map or nil if the link has already been visited or is invalid.
  """
  defp process_single_link(module, id, visited) when is_number(id) or is_binary(id) do
    case Map.get(visited, {module, id}) do
      nil ->
        case module.get_by_id(id) do
          nil ->
            nil

          data ->
            module.prepare_for_view(data)
        end

      _ ->
        nil
    end
  end

  defp process_single_link(module, data, visited) do
    case fetch_id(data) do
      {:ok, id} ->
        case Map.get(visited, {module, id}) do
          nil ->
            module.prepare_for_view(data)

          _ ->
            nil
        end

      :error ->
        nil
    end
  end

  @doc """
  Normalizes link IDs to always be a list.

  ## Parameters

  - `link_ids`: A single link ID or a list of link IDs

  ## Returns

  A list of link IDs.

  ## Examples

  iex> Carve.Links.normalize_link_ids(1)
  [1]

  iex> Carve.Links.normalize_link_ids([1, 2, 3])
  [1, 2, 3]
  """
  defp normalize_link_ids(link_ids) when is_list(link_ids), do: link_ids
  defp normalize_link_ids(link_id), do: [link_id]

  @doc """
  Fetches the ID from a data structure.

  This function attempts to find an ID in a map using various common key formats.

  ## Parameters

  - `data`: A map or other data structure potentially containing an ID

  ## Returns

  `{:ok, id}` if an ID is found, `:error` otherwise.

  ## Examples

  iex> Carve.Links.fetch_id(%{id: 1})
  {:ok, 1}

  iex> Carve.Links.fetch_id(%{"id" => 2})
  {:ok, 2}

  iex> Carve.Links.fetch_id(%{foo: "bar"})
  {:ok, {:foo, "bar"}}

  iex> Carve.Links.fetch_id("not a map")
  :error
  """
  defp fetch_id(data) when is_map(data) do
    cond do
      Map.has_key?(data, :id) ->
        {:ok, data.id}

      Map.has_key?(data, "id") ->
        {:ok, data["id"]}

      true ->
        case Enum.at(data, 0) do
          {key, value} -> {:ok, {key, value}}
          nil -> :error
        end
    end
  end

  defp fetch_id(id) when is_integer(id) or is_binary(id), do: {:ok, id}
  defp fetch_id(_), do: :error
end
