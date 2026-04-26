defmodule Comcent.DialUtilsTest do
  use ExUnit.Case, async: true
  alias Comcent.DialUtils

  describe "create_dial_string_for_user/2" do
    test "creates a proper dial string for a user" do
      # Save original environment
      original_sbc_ip = System.get_env("SBC_IP")

      # Set test environment
      System.put_env("SBC_IP", "192.168.1.100")

      expected =
        "sofia/internal/test_user@test_subdomain.example.com;fs_path=sip:192.168.1.100:5065,[media_webrtc=true]sofia/internal/test_user@test_subdomain.example.com;fs_path=sip:192.168.1.100:5065"

      assert DialUtils.create_dial_string_for_user("test_user", "test_subdomain") == expected

      # Restore original environment
      if original_sbc_ip do
        System.put_env("SBC_IP", original_sbc_ip)
      else
        System.delete_env("SBC_IP")
      end
    end
  end

  describe "create_dial_string_for_sip_trunk/4" do
    test "creates a proper dial string for a SIP trunk" do
      # Save original environment
      original_sbc_ip = System.get_env("SBC_IP")

      # Set test environment
      System.put_env("SBC_IP", "192.168.1.100")

      # Test without spoofed number
      expected_no_spoof =
        "[sip_h_X-Trunk-Number=11234567890,origination_caller_id_number=11234567890]sofia/internal/9876543210@example.com;fs_path=sip:192.168.1.100:5065"

      assert DialUtils.create_dial_string_for_sip_trunk(
               "11234567890",
               "9876543210",
               "example.com"
             ) ==
               expected_no_spoof

      # Test with spoofed number
      expected_with_spoof =
        "[sip_h_X-Trunk-Number=11234567890,origination_caller_id_number=5555555555]sofia/internal/9876543210@example.com;fs_path=sip:192.168.1.100:5065"

      assert DialUtils.create_dial_string_for_sip_trunk(
               "11234567890",
               "9876543210",
               "example.com",
               "5555555555"
             ) == expected_with_spoof

      # Restore original environment
      if original_sbc_ip do
        System.put_env("SBC_IP", original_sbc_ip)
      else
        System.delete_env("SBC_IP")
      end
    end
  end

  describe "convert_number_to_e164_or_us11/2" do
    test "converts phone numbers correctly according to reference format" do
      # Test cases from the TypeScript tests

      # US11 reference with E.164 number (remove +)
      assert DialUtils.convert_number_to_e164_or_us11("18002211212", "+18557876543") ==
               "18557876543"

      # E.164 reference with E.164 number (keep +)
      assert DialUtils.convert_number_to_e164_or_us11("+18002211212", "+18557876543") ==
               "+18557876543"

      # US11 reference with international E.164 number (remove +)
      assert DialUtils.convert_number_to_e164_or_us11("18002211212", "+919845012345") ==
               "919845012345"

      # US11 reference with international number without + (keep as is)
      assert DialUtils.convert_number_to_e164_or_us11("18002211212", "919845012345") ==
               "919845012345"

      # E.164 reference with international E.164 number (keep +)
      assert DialUtils.convert_number_to_e164_or_us11("+18002211212", "+919845012345") ==
               "+919845012345"

      # E.164 reference with international number without + (add +)
      assert DialUtils.convert_number_to_e164_or_us11("+18002211212", "919845012345") ==
               "+919845012345"
    end

    test "handles formatted numbers correctly" do
      # E.164 reference with formatted number (convert to E.164)
      assert DialUtils.convert_number_to_e164_or_us11("+18002211212", "(800)-221-1212") ==
               "+18002211212"

      # US11 reference with formatted number (convert to US11)
      assert DialUtils.convert_number_to_e164_or_us11("18002211212", "(800)-221-1212") ==
               "18002211212"
    end

    test "handles edge cases gracefully" do
      # Empty strings
      assert DialUtils.convert_number_to_e164_or_us11("18002211212", "") == ""
      assert DialUtils.convert_number_to_e164_or_us11("", "18002211212") == "+18002211212"

      # Special characters
      assert DialUtils.convert_number_to_e164_or_us11("18002211212", "#1234") == "#1234"
    end
  end
end
