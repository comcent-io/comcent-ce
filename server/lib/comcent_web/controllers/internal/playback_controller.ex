defmodule ComcentWeb.Internal.PlaybackController do
  use ComcentWeb, :controller
  require Logger

  # 1 hour in seconds
  @presigned_url_expiry 3600

  def head_playback(conn, %{"subdomain" => subdomain, "key" => key}) do
    bucket_name = Application.get_env(:comcent, :s3)[:storage_bucket_name]

    url = get_presigned_url(bucket_name, "#{subdomain}/playback/#{key}", :head)
    Logger.info("Presigned URL: #{url}")

    conn
    |> redirect(external: url)
  end

  def get_playback(conn, %{"subdomain" => subdomain, "key" => key}) do
    bucket_name = Application.get_env(:comcent, :s3)[:storage_bucket_name]

    url = get_presigned_url(bucket_name, "#{subdomain}/playback/#{key}")
    Logger.info("Presigned URL: #{url}")

    conn
    |> redirect(external: url)
  end

  # Helper functions

  defp get_presigned_url(bucket, path, method \\ :get) do
    region = Application.get_env(:comcent, :s3)[:bucket_region]
    config = ExAws.Config.new(:s3, region: region)

    {:ok, url} =
      ExAws.S3.presigned_url(config, method, bucket, path,
        expires_in: @presigned_url_expiry,
        virtual_host: true
      )

    url
  end
end
