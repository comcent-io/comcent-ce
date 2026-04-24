defmodule Comcent.Auth.Password do
  def hash(password) when is_binary(password) do
    Bcrypt.hash_pwd_salt(password)
  end

  def verify(password, password_hash)
      when is_binary(password) and is_binary(password_hash) and password_hash != "" do
    Bcrypt.verify_pass(password, password_hash)
  end

  def verify(_password, _password_hash), do: false
end
