defmodule Carve.HashIdsTest do
  use ExUnit.Case, async: true
  alias Carve.HashIds

  describe "with default configuration" do
    test "encodes and decodes correctly" do
      encoded = HashIds.encode(:user, 123)
      assert {:ok, 123} = HashIds.decode(:user, encoded)
    end

    test "encodes different types differently" do
      user_encoded = HashIds.encode(:user, 123)
      post_encoded = HashIds.encode(:post, 123)

      assert user_encoded != post_encoded
    end

    test "decodes only for the correct type" do
      encoded = HashIds.encode(:user, 123)
      assert {:ok, 123} = HashIds.decode(:user, encoded)
      assert {:error, :invalid_entity_type} = HashIds.decode(:post, encoded)
    end
  end

  describe "with custom configuration" do
    setup do
      HashIds.configure(salt: "custom_salt", min_length: 10)
      :ok
    end

    test "encodes with longer output" do
      encoded = HashIds.encode(:user, 123)
      assert String.length(encoded) >= 10
    end

    test "encodes and decodes correctly with custom config" do
      encoded = HashIds.encode(:user, 123)
      assert {:ok, 123} = HashIds.decode(:user, encoded)
    end
  end

  describe "decode_any" do
    test "decodes without checking entity type" do
      encoded = HashIds.encode(:user, 123)
      assert {:ok, 123} = HashIds.decode(encoded)
    end

    test "decodes hash from different entity types" do
      user_encoded = HashIds.encode(:user, 123)
      post_encoded = HashIds.encode(:post, 123)

      assert {:ok, 123} = HashIds.decode(user_encoded)
      assert {:ok, 123} = HashIds.decode(post_encoded)
    end
  end

  test "encodes and decodes large numbers" do
    large_id = 1_000_000_000
    encoded = HashIds.encode(:user, large_id)
    assert {:ok, ^large_id} = HashIds.decode(:user, encoded)
  end

  test "handles invalid input" do
    assert_raise FunctionClauseError, fn -> HashIds.encode("not_an_atom", 123) end
    assert_raise FunctionClauseError, fn -> HashIds.encode(:user, "not_an_integer") end
    assert_raise FunctionClauseError, fn -> HashIds.decode("not_an_atom", "abcdef") end
    #assert {:error, :invalid_hash} = HashIds.decode(:user, "invalid_entity_type")
  end

  test "different salts produce different encodings" do
    HashIds.configure(salt: "salt1")
    encoded1 = HashIds.encode(:user, 123)

    HashIds.configure(salt: "salt2")
    encoded2 = HashIds.encode(:user, 123)

    assert encoded1 != encoded2
  end

  test "encodes and decodes zero" do
    encoded = HashIds.encode(:user, 0)
    assert {:ok, 0} = HashIds.decode(:user, encoded)
  end
end
