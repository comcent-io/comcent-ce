defmodule Comcent.OutboundPattern do
  @moduledoc """
  A number's `allow_outbound_regex`: the destinations an outside call placed
  from that number is allowed to reach. Empty (nil, "" or only whitespace)
  means unrestricted.

  ## What the pattern is matched against

  The destination as it is actually sent to the carrier, not as it was typed.
  Before an outside call leaves on a trunk, the dialled string is rewritten by
  `Comcent.DialUtils.convert_number_to_e164_or_us11/2` relative to the number
  placing the call (see `Comcent.DialUtils.create_dial_string_for_sip_trunk/4`):

    * a number stored in E.164 (`+14155550100`) sends E.164, so a destination
      dialled as `14155550123` or `(415) 555-0123` is checked as `+14155550123`;
    * a number stored in the US 11-digit form (`14155550100`) sends the
      destination without the `+` (`14155550123`). For those, the E.164
      spelling of the same destination (`+14155550123`) is checked too, so a
      pattern written in E.164, as the number settings suggest, works for
      every number.

  Checking what the carrier receives, rather than the raw dialled string, is
  what makes the restriction hold: any other reading would let a caller type
  something that passes the check yet reaches a different number once it is
  normalised.

  The pattern is an ordinary (PCRE) regular expression and is not anchored
  for you: `^\\+1[0-9]{10}$` allows only North American numbers, while `\\+1`
  would allow any destination that merely contains `+1`.
  """

  alias Comcent.DialUtils

  @doc """
  Whether `pattern` can be saved: `:ok` for a valid or empty pattern, otherwise
  `{:error, message}` describing why it does not compile.
  """
  def validate(pattern) do
    case compile(pattern) do
      {:ok, _} -> :ok
      {:error, {reason, position}} -> {:error, invalid_message(reason, position)}
    end
  end

  @doc """
  Whether an outside call from `from_number` to `destination` is allowed by
  `pattern`.

  Returns `:ok`, `{:error, :destination_not_allowed}`, or
  `{:error, :invalid_pattern}` when the stored pattern does not compile - which
  refuses the call rather than letting a broken restriction allow everything.
  """
  def check(pattern, from_number, destination) do
    case compile(pattern) do
      {:ok, :unrestricted} ->
        :ok

      {:ok, regex} ->
        if Enum.any?(match_targets(from_number, destination), &Regex.match?(regex, &1)),
          do: :ok,
          else: {:error, :destination_not_allowed}

      {:error, _} ->
        {:error, :invalid_pattern}
    end
  end

  @doc """
  The spellings of `destination` a pattern is tested against when calling from
  `from_number`: the one the carrier receives and, for a US 11-digit number,
  its E.164 equivalent.
  """
  def match_targets(from_number, destination) do
    sent = DialUtils.convert_number_to_e164_or_us11(from_number, destination)

    if us11?(from_number) and Regex.match?(~r/^1\d{10}$/, sent) do
      [sent, "+" <> sent]
    else
      [sent]
    end
  end

  defp compile(nil), do: {:ok, :unrestricted}

  defp compile(pattern) when is_binary(pattern) do
    if String.trim(pattern) == "" do
      {:ok, :unrestricted}
    else
      Regex.compile(pattern)
    end
  end

  # The same test convert_number_to_e164_or_us11/2 uses to decide the format.
  defp us11?(number), do: String.length(number) == 11 and String.starts_with?(number, "1")

  defp invalid_message(reason, position) do
    "is not a valid regular expression (#{reason} at position #{position})"
  end
end
