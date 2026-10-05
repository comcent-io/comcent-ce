defmodule Comcent.OutboundContact do
  @moduledoc """
  A SIP trunk's `outbound_contact`: the carrier address its outbound calls are
  sent to.

  Customers type it in any of these forms, with or without surrounding spaces:

    * `host` - `sip.example.com`, `203.0.113.10`
    * `host:port` - `sip.example.com:5080`
    * `sip:host` / `sip:host:port`

  It is stored in one canonical form, the bare `host` or `host:port`, because
  that is what both readers expect: FreeSWITCH puts it after the `@` of the
  trunk dial string (`Comcent.DialUtils.create_dial_string_for_sip_trunk/4`),
  and the SBC splits it on `:` into the host and port it sends the INVITE to.
  Leaving the `sip:` on would make the SBC read `sip` as the host.

  What neither reader can honour is refused rather than dropped silently:

    * `sips:` - the SBC reaches carriers over plain UDP, there is no TLS leg;
    * URI parameters such as `;transport=tcp`, and a `user@` part - the SBC
      builds the request URI from the host and port alone;
    * IPv6 addresses - the SBC's `host:port` split cannot tell an IPv6
      address's colons from the port separator.
  """

  @format_hint "Use host, host:port, sip:host or sip:host:port, e.g. sip:sip.example.com:5060"

  @doc """
  Parses what a customer typed into the canonical stored form.

  Returns `{:ok, "host"}` or `{:ok, "host:port"}`, or `{:error, message}`
  with a message that can be shown next to the field.

      iex> Comcent.OutboundContact.normalize(" sip:sip.example.com:5080 ")
      {:ok, "sip.example.com:5080"}

      iex> Comcent.OutboundContact.normalize("sips:sip.example.com")
      {:error, "sips: (TLS) is not supported. Use sip:host or sip:host:port"}
  """
  def normalize(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:error, "can't be blank. " <> @format_hint}

      String.match?(value, ~r/\s/) ->
        {:error, "must not contain spaces. " <> @format_hint}

      String.match?(value, ~r/^sips:/i) ->
        {:error, "sips: (TLS) is not supported. Use sip:host or sip:host:port"}

      true ->
        value |> strip_sip_scheme() |> parse_address()
    end
  end

  def normalize(_), do: {:error, "is invalid. " <> @format_hint}

  @doc """
  The address to dial for a stored value.

  Lenient on purpose: rows written before the value was validated may still
  carry a `sip:` prefix or stray spaces, and those must keep dialling.

      iex> Comcent.OutboundContact.dial_address("sip:sip.example.com:5080")
      "sip.example.com:5080"
  """
  def dial_address(nil), do: nil

  def dial_address(value) when is_binary(value) do
    value |> String.trim() |> strip_sip_scheme()
  end

  defp strip_sip_scheme(value), do: String.replace(value, ~r/^sip:/i, "")

  defp parse_address(address) do
    cond do
      String.contains?(address, ";") ->
        {:error,
         "URI parameters such as ;transport=tcp are not supported (calls go out over UDP). " <>
           @format_hint}

      String.contains?(address, "@") ->
        {:error, "must be the carrier's address only, without a user@ part. " <> @format_hint}

      # More than one colon: an IPv6 address, or "sip:host:port" with a
      # second scheme in front of it.
      String.contains?(address, "[") or length(String.split(address, ":")) > 2 ->
        {:error, "is not a valid SIP address. IPv6 addresses are not supported. " <> @format_hint}

      # Another scheme ("http://host", or a doubled "sip:sip:host"): a
      # dot-less word before the colon that is not followed by a port.
      String.match?(address, ~r/^[a-z][a-z0-9+-]*:(?!\d+$)/i) ->
        {:error, "only the sip: scheme is supported. " <> @format_hint}

      true ->
        case String.split(address, ":") do
          [host] -> with_host(host, nil)
          [host, port] -> with_host(host, port)
        end
    end
  end

  defp with_host(host, port) do
    cond do
      not valid_host?(host) ->
        {:error, "has an invalid host name or IP address. " <> @format_hint}

      port == nil ->
        {:ok, host}

      true ->
        case parse_port(port) do
          {:ok, port} -> {:ok, "#{host}:#{port}"}
          :error -> {:error, "has an invalid port, it must be 1-65535. " <> @format_hint}
        end
    end
  end

  defp parse_port(port) do
    with true <- String.match?(port, ~r/^\d{1,5}$/),
         number when number in 1..65_535 <- String.to_integer(port) do
      {:ok, number}
    else
      _ -> :error
    end
  end

  # Digits and dots only must be a real IPv4 address, so "1.0.5" or
  # "265.1.0.5" is refused instead of being taken for a host name.
  defp valid_host?(host) do
    if String.match?(host, ~r/^[\d.]+$/) do
      valid_ipv4?(host)
    else
      valid_hostname?(host)
    end
  end

  defp valid_ipv4?(host) do
    case String.split(host, ".") do
      octets when length(octets) == 4 ->
        Enum.all?(octets, fn octet ->
          String.match?(octet, ~r/^\d{1,3}$/) and String.to_integer(octet) <= 255
        end)

      _ ->
        false
    end
  end

  # RFC 1123 labels. A single label is allowed (an internal host such as a
  # container name), but the last label must not be all digits.
  defp valid_hostname?(host) do
    labels = String.split(host, ".")

    String.length(host) <= 253 and
      Enum.all?(labels, &String.match?(&1, ~r/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/i)) and
      not String.match?(List.last(labels), ~r/^\d+$/)
  end
end
