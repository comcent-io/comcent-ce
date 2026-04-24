defmodule ComcentWeb.FileController do
  use ComcentWeb, :controller

  require Logger

  @presigned_url_expiry 120

  def get_playback(conn, %{"subdomain" => subdomain, "file_name" => file_name}) do
    redirect_to_signed_object(conn, playback_key(subdomain, file_name), false)
  end

  def get_recording(conn, %{"subdomain" => subdomain, "file_name" => file_name}) do
    serve_or_redirect_object(conn, recording_key(subdomain, file_name), true)
  end

  def get_compliance_download(conn, %{"subdomain" => subdomain, "file_name" => file_name}) do
    redirect_to_signed_object(conn, compliance_download_key(subdomain, file_name), true)
  end

  def get_upload_signed_url(conn, %{"subdomain" => subdomain} = params) do
    filename = String.trim(params["filename"] || "")
    access = String.trim(params["access"] || "get")

    cond do
      filename == "" ->
        conn |> put_status(:bad_request) |> json(%{error: "Need file name"})

      access not in ["get", "put", "delete"] ->
        conn |> put_status(:bad_request) |> json(%{error: "Invalid access type."})

      true ->
        {_, bucket} = Comcent.S3.get_s3_config()

        case Comcent.S3.get_pre_signed_url(
               bucket,
               playback_key(subdomain, filename),
               access_method(access),
               @presigned_url_expiry
             ) do
          nil ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Could not create a pre-signed URL."})

          url ->
            json(conn, %{url: url})
        end
    end
  end

  def delete_upload(conn, %{"subdomain" => subdomain} = params) do
    filename = String.trim(params["filename"] || "")

    if filename == "" do
      conn |> put_status(:bad_request) |> json(%{error: "File name is required"})
    else
      {region, bucket} = Comcent.S3.get_s3_config()
      config = ExAws.Config.new(:s3, region: region, service: :s3)

      case ExAws.S3.delete_object(bucket, playback_key(subdomain, filename))
           |> ExAws.request(config) do
        {:ok, _} ->
          json(conn, %{message: "File deleted successfully"})

        {:error, error} ->
          Logger.error("Error deleting file from S3: #{inspect(error)}")

          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Error deleting file"})
      end
    end
  end

  defp redirect_to_signed_object(conn, key, check_exists?) do
    {_, bucket} = Comcent.S3.get_s3_config()

    signed_url =
      if check_exists? and not object_exists?(bucket, key) do
        nil
      else
        Comcent.S3.get_pre_signed_url(bucket, key)
      end

    if signed_url do
      redirect(conn, external: signed_url)
    else
      conn |> put_status(:not_found) |> json(%{error: "File not found"})
    end
  end

  defp serve_or_redirect_object(conn, key, check_exists?) do
    if System.get_env("S3_PROXY_DOWNLOADS", "false") == "true" do
      proxy_object(conn, key, check_exists?)
    else
      redirect_to_signed_object(conn, key, check_exists?)
    end
  end

  defp proxy_object(conn, key, check_exists?) do
    {region, bucket} = Comcent.S3.get_s3_config()
    config = ExAws.Config.new(:s3, region: region, service: :s3)

    if check_exists? and not object_exists?(bucket, key) do
      conn |> put_status(:not_found) |> json(%{error: "File not found"})
    else
      case ExAws.S3.get_object(bucket, key) |> ExAws.request(config) do
        {:ok, %{body: body, headers: headers}} ->
          content_type =
            headers
            |> Enum.find_value("application/octet-stream", fn
              {"Content-Type", value} -> value
              {"content-type", value} -> value
              _ -> nil
            end)

          conn
          |> put_resp_content_type(content_type)
          |> send_resp(:ok, body)

        {:error, error} ->
          Logger.error("Error fetching file from S3: #{inspect(error)}")
          conn |> put_status(:not_found) |> json(%{error: "File not found"})
      end
    end
  end

  defp object_exists?(bucket, key) do
    {region, _} = Comcent.S3.get_s3_config()
    config = ExAws.Config.new(:s3, region: region, service: :s3)

    case ExAws.S3.head_object(bucket, key) |> ExAws.request(config) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp access_method("get"), do: :get
  defp access_method("put"), do: :put
  defp access_method("delete"), do: :delete

  defp playback_key(subdomain, file_name), do: "#{subdomain}/playback/#{file_name}"
  defp recording_key(subdomain, file_name), do: "#{subdomain}/recording/#{file_name}"

  defp compliance_download_key(subdomain, file_name) do
    "#{subdomain}/compliance/downloads/#{file_name}"
  end
end
