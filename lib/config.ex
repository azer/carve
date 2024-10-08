defmodule Carve.Config do
  @moduledoc """
  Handles configuration for Carve.
  """

  @doc """
  Retrieves the configuration for Carve.
  """
  def get do
    Application.get_env(:carve, __MODULE__, [])
  end

  @doc """
  Gets a specific configuration value.
  """
  def get(key, default \\ nil) do
    get()
    |> Keyword.get(key, default)
  end
end
