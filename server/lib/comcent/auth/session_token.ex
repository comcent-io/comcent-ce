defmodule Comcent.Auth.SessionToken do
  @default_expiry_seconds 30 * 24 * 60 * 60

  def sign(claims, expires_in_seconds \\ @default_expiry_seconds) do
    now = System.system_time(:second)

    merged_claims =
      claims
      |> Map.put_new("iat", now)
      |> Map.put_new("exp", now + expires_in_seconds)

    signer()
    |> JOSE.JWT.sign(%{"alg" => "HS256"}, JOSE.JWT.from_map(merged_claims))
    |> JOSE.JWS.compact()
    |> elem(1)
  end

  def verify(token) do
    case JOSE.JWT.verify_strict(signer(), ["HS256"], token) do
      {true, jwt, _jws} ->
        claims = jwt.fields

        if expired?(claims) do
          {:error, :token_expired}
        else
          {:ok, claims}
        end

      {false, _, _} ->
        {:error, :invalid_token}
    end
  rescue
    _ -> {:error, :invalid_token}
  end

  defp signer do
    signing_key =
      System.get_env("SIGNING_KEY") ||
        raise """
        environment variable SIGNING_KEY is missing.
        """

    JOSE.JWK.from_oct(signing_key)
  end

  defp expired?(%{"exp" => exp}) when is_integer(exp) do
    System.system_time(:second) >= exp
  end

  defp expired?(_claims), do: true
end
