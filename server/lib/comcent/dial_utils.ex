defmodule Comcent.DialUtils do
  @moduledoc """
  Utility functions for handling dial strings and phone number formatting.
  This is the Elixir equivalent of the TypeScript dialUtils.ts file.
  """

  @doc """
  Creates a dial string for a user.

  Uses the `:sip_user_root_domain` application config (backed by SIP_USER_ROOT_DOMAIN env var,
  or derived from PUBLIC_BASE_URL).
  """
  def create_dial_string_for_user(username, subdomain, channel_vars \\ nil) do
    create_dial_targets_for_user(username, subdomain, channel_vars)
    |> Enum.join(",")
  end

  def create_dial_targets_for_user(username, subdomain, channel_vars \\ nil) do
    sbc_sip_uri = sbc_sip_uri()
    sip_user_root_domain = Application.fetch_env!(:comcent, :sip_user_root_domain)
    base_dial = "sofia/internal/#{username}@#{subdomain}.#{sip_user_root_domain};fs_path=#{sbc_sip_uri}"
    build_user_dial_targets(base_dial, channel_vars)
  end

  # Target the SBC's PRIVATE listener (5065). 5060 is the public/PSTN-facing
  # leg; sending FS outbound there would loop back through public routing.
  defp sbc_sip_uri do
    case System.get_env("SBC_IP") do
      nil -> ""
      "" -> ""
      ip -> "sip:#{ip}:5065"
    end
  end

  def user_dial_branch_count do
    2
  end

  defp build_user_dial_targets(base_dial, channel_vars) do
    vars = channel_vars || []

    [
      maybe_prefix_channel_vars(base_dial, vars),
      maybe_prefix_channel_vars(base_dial, vars ++ ["media_webrtc=true"])
    ]
  end

  defp maybe_prefix_channel_vars(dial_string, channel_vars) do
    if Enum.empty?(channel_vars) do
      dial_string
    else
      "[#{Enum.join(channel_vars, ",")}]#{dial_string}"
    end
  end

  @doc """
  Creates a dial string for a SIP trunk.

  ## Examples

      iex> Comcent.DialUtils.create_dial_string_for_sip_trunk("1234567890", "9876543210", "sip.example.com")
      "[sip_h_X-Trunk-Number=1234567890,origination_caller_id_number=1234567890]sofia/internal/9876543210@sip.example.com;fs_path=sbc_sip_uri"

      iex> Comcent.DialUtils.create_dial_string_for_sip_trunk("1234567890", "9876543210", "sip.example.com", "5555555555")
      "[sip_h_X-Trunk-Number=1234567890,origination_caller_id_number=5555555555]sofia/internal/9876543210@sip.example.com;fs_path=sbc_sip_uri"
  """
  def create_dial_string_for_sip_trunk(
        from_number,
        to_number,
        trunk_address,
        spoofed_number \\ nil
      ) do
    sbc_sip_uri = sbc_sip_uri()

    # Convert numbers to E164 or US11 format
    adjusted_to_number = convert_number_to_e164_or_us11(from_number, to_number)

    adjusted_spoofed_number =
      if spoofed_number,
        do: convert_number_to_e164_or_us11(from_number, spoofed_number),
        else: nil

    caller_id = adjusted_spoofed_number || from_number

    variables =
      "[sip_h_X-Trunk-Number=#{from_number},origination_caller_id_number=#{caller_id}]"

    "#{variables}sofia/internal/#{adjusted_to_number}@#{trunk_address};fs_path=#{sbc_sip_uri}"
  end

  @doc """
  Converts a phone number to E164 or US11 format based on a reference number.

  This is a simplified implementation without using ex_phone_number library.
  For a complete implementation, consider using a proper phone number parsing library.

  ## Examples

      iex> Comcent.DialUtils.convert_number_to_e164_or_us11("18002211212", "+18557876543")
      "18557876543"

      iex> Comcent.DialUtils.convert_number_to_e164_or_us11("+18002211212", "+919845012345")
      "+919845012345"
  """
  def convert_number_to_e164_or_us11(reference_number, number_to_be_converted) do
    # Check if the reference is in US11 format (11 digits starting with 1)
    is_us11 = String.length(reference_number) == 11 && String.starts_with?(reference_number, "1")

    # For this simplified version, we're handling the basic cases
    cond do
      # If reference is US11 and converted number starts with +, remove the +
      is_us11 && String.starts_with?(number_to_be_converted, "+") ->
        String.replace_prefix(number_to_be_converted, "+", "")

      # If reference is not US11 (E.164) and converted number doesn't have +, add it
      !is_us11 && !String.starts_with?(number_to_be_converted, "+") &&
        String.length(number_to_be_converted) > 9 &&
          String.match?(number_to_be_converted, ~r/^\d+$/) ->
        "+#{number_to_be_converted}"

      # Handle formatted numbers like (800)-221-1212
      is_us11 && String.match?(number_to_be_converted, ~r/\D/) ->
        # Extract just the digits
        digits = Regex.replace(~r/\D/, number_to_be_converted, "")

        # If it looks like a US number (10 or 11 digits), format as US11
        if String.length(digits) >= 10 do
          digits = if String.length(digits) == 10, do: "1#{digits}", else: digits
          # Return with appropriate format
          if String.length(digits) == 11 && String.starts_with?(digits, "1"),
            do: digits,
            else: digits
        else
          number_to_be_converted
        end

      # Handle formatted numbers for E.164
      !is_us11 && String.match?(number_to_be_converted, ~r/\D/) ->
        # Extract just the digits
        digits = Regex.replace(~r/\D/, number_to_be_converted, "")

        # If it looks like a valid number, format as E.164
        if String.length(digits) >= 10 do
          digits = if String.length(digits) == 10, do: "1#{digits}", else: digits
          # Return with appropriate format
          if String.length(digits) >= 11, do: "+#{digits}", else: "+1#{digits}"
        else
          number_to_be_converted
        end

      # Otherwise keep the number as is
      true ->
        number_to_be_converted
    end
  end
end
