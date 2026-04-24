defmodule Comcent.S3 do
  @moduledoc """
  Module for handling S3 operations including generating pre-signed URLs.
  """

  require Logger

  # 7 days in seconds
  @default_expires_in 60 * 60 * 24 * 7

  @doc """
  Gets the S3 configuration from runtime.exs through application config.
  """
  def get_s3_config do
    bucket_region = Application.get_env(:ex_aws, :region)
    storage_bucket_name = Application.get_env(:comcent, :storage)[:bucket_name]
    {bucket_region, storage_bucket_name}
  end

  @doc """
  Generates a pre-signed URL for S3 operations.

  ## Parameters
    - bucket: The S3 bucket name
    - key: The object key
    - method: The HTTP method (:get, :head, :put)
    - expires_in: Time in seconds until the URL expires (default: 7 days)

  ## Returns
    - The pre-signed URL as a string or nil if generation fails
  """
  def get_pre_signed_url(bucket, key, method \\ :get, expires_in \\ @default_expires_in) do
    try do
      {region, _} = get_s3_config()

      # Ensure key is properly encoded
      encoded_key = URI.encode(key)

      Logger.debug("Generating pre-signed URL for bucket: #{bucket}, key: #{encoded_key}")

      if is_nil(bucket) or bucket == "" do
        raise "Invalid bucket name: #{inspect(bucket)}"
      end

      case ExAws.S3.presigned_url(
             ExAws.Config.new(:s3, region: region),
             method,
             bucket,
             encoded_key,
             expires_in: expires_in
           ) do
        {:ok, url} ->
          url

        error ->
          Logger.error("Failed to generate pre-signed URL: #{inspect(error)}")
          nil
      end
    rescue
      e ->
        Logger.error("Error generating pre-signed URL: #{inspect(e)}")
        nil
    end
  end

  @doc """
  Generates a pre-signed URL specifically for recording files.

  ## Parameters
    - subdomain: The subdomain identifier
    - file_name: The name of the recording file
    - method: The HTTP method (:get, :head, :put)
    - expires_in: Time in seconds until the URL expires (default: 7 days)

  ## Returns
    - The pre-signed URL as a string or nil if generation fails
  """
  def get_recording_pre_signed_url(
        subdomain,
        file_name,
        method \\ :get,
        expires_in \\ @default_expires_in
      ) do
    try do
      # Ensure subdomain and file_name are strings
      subdomain = to_string(subdomain)
      file_name = to_string(file_name)

      # Construct the key with proper path separators
      key = Path.join([subdomain, "recording", file_name])
      {_, bucket} = get_s3_config()

      Logger.debug(
        "Generating recording URL for subdomain: #{subdomain}, file: #{file_name}, bucket: #{bucket}"
      )

      get_pre_signed_url(bucket, key, method, expires_in)
    rescue
      e ->
        Logger.error("Error in get_recording_pre_signed_url: #{inspect(e)}")
        nil
    end
  end
end
