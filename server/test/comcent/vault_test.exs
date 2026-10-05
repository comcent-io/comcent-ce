defmodule Comcent.VaultTest do
  # Not async: one group switches the vault's key off in the application env.
  use ExUnit.Case, async: false

  alias Comcent.Encrypted.Map, as: EncryptedMap

  describe "Comcent.Encrypted.Map" do
    test "round-trips a credential map" do
      credentials = %{"api_key_sid" => "SK123", "api_key_secret" => "shhh"}

      assert {:ok, ciphertext} = EncryptedMap.dump(credentials)
      assert is_binary(ciphertext)
      assert {:ok, ^credentials} = EncryptedMap.load(ciphertext)
    end

    test "ciphertext does not contain the plaintext secret" do
      secret = "super-secret-api-key-value"
      {:ok, ciphertext} = EncryptedMap.dump(%{"api_key_secret" => secret})

      refute String.contains?(ciphertext, secret)
    end

    test "encrypting the same value twice yields different ciphertext" do
      credentials = %{"api_key_secret" => "same-value"}

      {:ok, first} = EncryptedMap.dump(credentials)
      {:ok, second} = EncryptedMap.dump(credentials)

      # AES.GCM uses a random IV per write, so identical credentials must not
      # produce identical rows — otherwise the database leaks which tenants
      # share a key.
      refute first == second
      assert {:ok, ^credentials} = EncryptedMap.load(first)
      assert {:ok, ^credentials} = EncryptedMap.load(second)
    end

    test "handles nil" do
      assert {:ok, nil} = EncryptedMap.dump(nil)
      assert {:ok, nil} = EncryptedMap.load(nil)
    end

    test "loads a value that was stored before a key was configured" do
      credentials = %{"api_key_sid" => "SK123", "api_key_secret" => "shhh"}

      assert {:ok, ^credentials} = EncryptedMap.load(Jason.encode!(credentials))
    end
  end

  describe "without PROVIDER_CREDENTIALS_KEY" do
    setup do
      previous = Application.get_env(:comcent, Comcent.Vault)
      Application.put_env(:comcent, Comcent.Vault, key: nil)
      on_exit(fn -> Application.put_env(:comcent, Comcent.Vault, previous) end)
    end

    test "stores the credential map as plain JSON" do
      credentials = %{"api_key_sid" => "SK123", "api_key_secret" => "shhh"}

      assert {:ok, stored} = EncryptedMap.dump(credentials)
      assert Jason.decode!(stored) == credentials
      assert {:ok, ^credentials} = EncryptedMap.load(stored)
    end

    test "refuses a value that was encrypted with a key" do
      Application.put_env(:comcent, Comcent.Vault, key: Base.encode64(:binary.copy(<<0>>, 32)))
      {:ok, ciphertext} = EncryptedMap.dump(%{"api_key_secret" => "shhh"})
      Application.put_env(:comcent, Comcent.Vault, key: nil)

      assert :error = EncryptedMap.load(ciphertext)
    end
  end
end
