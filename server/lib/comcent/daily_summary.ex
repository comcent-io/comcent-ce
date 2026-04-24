defmodule Comcent.DailySummary do
  @moduledoc """
  Handles daily summary operations for organizations.
  This module is called by the Quantum scheduler to process daily summaries
  for organizations that have them enabled at their specified time and timezone.
  """
  require Logger
  alias Comcent.Repo
  alias Comcent.Schemas.{Org, DailySummary, Promises}
  alias Comcent.Repo.Org
  alias Comcent.Repo.CallTranscript
  alias Comcent.OpenAI
  import Ecto.Query

  @doc """
  Main function to run daily summary operations.
  This is called by the Quantum scheduler.
  """
  def generate_daily_summaries do
    Logger.info("Daily summary job started")

    case get_orgs_and_process() do
      {:ok, _result} ->
        Logger.info("Daily summary job completed successfully")
        :ok

      {:error, error} ->
        Logger.error("Daily summary job failed: #{inspect(error)}")
        :error
    end
  end

  defp get_orgs_and_process do
    # Get current time in UTC
    now_utc = DateTime.utc_now()

    # Find all organizations that have daily summary enabled
    orgs_with_daily_summary = Org.get_orgs_with_daily_summary_enabled()

    Logger.info(
      "Found #{length(orgs_with_daily_summary)} organizations with daily summary enabled"
    )

    # Process each organization
    Enum.each(orgs_with_daily_summary, fn org ->
      process_org_daily_summary(org, now_utc)
    end)

    {:ok, :processed}
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Processes daily summary for a specific organization if it's time to run it.
  """
  def process_org_daily_summary(org, now_utc) do
    case should_run_daily_summary(org, now_utc) do
      true ->
        Logger.info("Running daily summary for org #{org.subdomain}")
        run_daily_summary_for_org(org)

      false ->
        :ok
    end
  end

  @doc """
  Determines if the daily summary should run for an organization based on current time.
  Runs only at the exact scheduled time to avoid duplicates.
  """
  def should_run_daily_summary(org, now_utc) do
    case parse_time_and_check(org, now_utc) do
      {:ok, should_run} ->
        should_run

      {:error, error} ->
        Logger.error(
          "Error checking daily summary time for org #{org.subdomain}: #{inspect(error)}"
        )

        false
    end
  end

  defp parse_time_and_check(org, now_utc) do
    # Parse the time string (format: "HH:MM" or "HH:MM:SS")
    time_parts =
      org.daily_summary_time
      |> String.split(":")
      |> Enum.map(&String.to_integer/1)

    # Handle both "HH:MM" and "HH:MM:SS" formats
    {hours, minutes, seconds} =
      case time_parts do
        # Default seconds to 0 if not provided
        [h, m] -> {h, m, 0}
        [h, m, s] -> {h, m, s}
        _ -> raise "Invalid time format: #{org.daily_summary_time}"
      end

    # Get the timezone
    timezone = org.daily_summary_time_zone

    # Create a datetime in the org's timezone for today
    {:ok, %DateTime{} = org_now} = DateTime.now(timezone)

    # Create the target time for today in the org's timezone
    target_time_today = %DateTime{
      org_now
      | hour: hours,
        minute: minutes,
        second: seconds,
        microsecond: {0, 6}
    }

    # Convert to UTC for comparison
    target_time_utc = DateTime.shift_zone!(target_time_today, "Etc/UTC")

    # Check if we're at the exact target time (same minute)
    time_diff_minutes = DateTime.diff(now_utc, target_time_utc, :minute)

    # Run only if we're at the exact target time (0 minutes difference)
    {:ok, time_diff_minutes == 0}
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Runs the daily summary process for a specific organization.
  """
  def run_daily_summary_for_org(org) do
    Logger.info("Running daily summary for organization: #{org.subdomain}")

    # Check if summary already exists for today (UTC) before generating
    # This prevents unnecessary API calls and duplicate generation
    today_utc = DateTime.utc_now() |> DateTime.to_date()

    case has_daily_summary_for_date?(org.id, today_utc) do
      true ->
        Logger.info(
          "Daily summary already exists for org #{org.subdomain} for today (UTC date: #{Date.to_string(today_utc)}). Skipping generation."
        )

        :ok

      false ->
        Logger.info(
          "No existing summary found for org #{org.subdomain} for today. Proceeding with generation..."
        )

        transcripts = CallTranscript.get_transcripts_by_subdomain(org.subdomain)

        Logger.info("Found #{length(transcripts)} transcripts for #{org.subdomain}")

        # Format transcripts into the required call format
        formatted_transcripts = format_transcripts_for_summary(transcripts)

        case generate_daily_summary(formatted_transcripts) do
          {:ok, result} ->
            Logger.info("Daily summary generated successfully for #{org.subdomain}")

            # Save the daily summary to the database
            case save_daily_summary(result, org.id) do
              {:ok, _daily_summary} ->
                Logger.info("Daily summary saved successfully for #{org.subdomain}")
                :ok

              {:error, error} ->
                Logger.error("Error saving daily summary for #{org.subdomain}: #{inspect(error)}")
                :error
            end

          {:error, error} ->
            Logger.error("Error generating daily summary for #{org.subdomain}: #{inspect(error)}")
            :error
        end
    end
  end

  @doc """
  Formats transcripts into the required call format for summary generation.
  """
  def format_transcripts_for_summary(transcripts) do
    transcripts
    |> Enum.map(fn %{
                     caller: caller,
                     callee: callee,
                     start_at: start_at,
                     duration: duration,
                     transcript: transcript
                   } ->
      """
      <call>
      From: #{caller}
      To: #{callee}
      Time: #{start_at}
      Duration: #{duration}
      Transcript: #{transcript}
      </call>
      """
    end)
    |> Enum.join("\n")
  end

  defp generate_daily_summary(formatted_transcripts) do
    # Count tokens in the base prompt (without transcripts)
    base_prompt = """
    You are analyzing transcripts from multiple customer support calls.
    Each call is formatted with caller information, timing, duration, and transcript content.

    Your task:
    - Read all call transcripts carefully.
    - Generate a comprehensive executive summary in markdown format that covers:
      - Overall call volume and patterns
      - Key customer issues and concerns
      - Service quality observations
      - Critical incidents or escalations
      - Follow-up actions needed
      - Performance insights

    Return the result as a well-structured markdown document with appropriate headings, bullet points, and formatting.

    Call transcripts:
    """

    base_tokens = count_tokens(base_prompt)
    transcript_tokens = count_tokens(formatted_transcripts)
    total_tokens = base_tokens + transcript_tokens

    Logger.info(
      "Total tokens in prompt: #{total_tokens} (base: #{base_tokens}, transcripts: #{transcript_tokens})"
    )

    # If total tokens exceed 1M, split into chunks
    if total_tokens > 1_000_000 do
      Logger.info("Token limit exceeded, splitting transcripts into chunks")
      generate_chunked_daily_summary(formatted_transcripts, base_prompt)
    else
      # Generate summary normally for smaller datasets
      generate_single_daily_summary(formatted_transcripts, base_prompt)
    end
  end

  defp generate_single_daily_summary(formatted_transcripts, base_prompt) do
    prompt = base_prompt <> formatted_transcripts

    messages = [%{"role" => "user", "content" => prompt}]

    case OpenAI.chat_completion(messages, 0, "gpt-4.1") do
      {:ok, response_content} ->
        {:ok, response_content}

      {:error, error} ->
        Logger.error("OpenAI API error: #{inspect(error)}")
        {:error, error}
    end
  end

  defp generate_chunked_daily_summary(formatted_transcripts, base_prompt) do
    # Split transcripts into chunks that fit within token limits
    chunks = split_transcripts_into_chunks(formatted_transcripts, base_prompt)

    Logger.info("Split transcripts into #{length(chunks)} chunks")

    # Generate partial summaries for each chunk
    partial_summaries = generate_partial_summaries(chunks, base_prompt)

    case partial_summaries do
      {:ok, summaries} ->
        # Generate final summary from all partial summaries
        generate_final_summary(summaries)

      {:error, error} ->
        {:error, error}
    end
  end

  defp split_transcripts_into_chunks(formatted_transcripts, base_prompt) do
    # Split by individual calls (each call is wrapped in <call> tags)
    call_pattern = ~r/<call>[\s\S]*?<\/call>/
    calls = Regex.scan(call_pattern, formatted_transcripts) |> Enum.map(&hd/1)

    Logger.info("Found #{length(calls)} individual calls")

    # Calculate max tokens per chunk (leave room for base prompt and final summary)
    # Conservative limit
    max_tokens_per_chunk = 800_000
    base_tokens = count_tokens(base_prompt)
    available_tokens_per_chunk = max_tokens_per_chunk - base_tokens

    # Group calls into chunks
    {final_chunks, remaining_chunk} =
      Enum.reduce(calls, {[], []}, fn call, {chunks_acc, current_chunk_acc} ->
        call_tokens = count_tokens(call)

        current_chunk_tokens =
          Enum.reduce(current_chunk_acc, 0, fn c, acc -> acc + count_tokens(c) end)

        # If adding this call would exceed the limit, start a new chunk
        if current_chunk_tokens + call_tokens > available_tokens_per_chunk &&
             length(current_chunk_acc) > 0 do
          new_chunk = Enum.join(current_chunk_acc, "\n")
          {chunks_acc ++ [new_chunk], [call]}
        else
          {chunks_acc, current_chunk_acc ++ [call]}
        end
      end)

    # Add the last chunk if it has content
    if length(remaining_chunk) > 0 do
      last_chunk = Enum.join(remaining_chunk, "\n")
      final_chunks ++ [last_chunk]
    else
      final_chunks
    end
  end

  defp generate_partial_summaries(chunks, base_prompt) do
    Logger.info("Generating partial summaries for #{length(chunks)} chunks")

    partial_summaries =
      chunks
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {chunk, index}, {:ok, acc} ->
        Logger.info("Processing chunk #{index}/#{length(chunks)}")

        prompt = base_prompt <> chunk

        case OpenAI.chat_completion([%{"role" => "user", "content" => prompt}], 0, "gpt-4.1") do
          {:ok, response_content} ->
            {:cont, {:ok, acc ++ [response_content]}}

          {:error, error} ->
            Logger.error("OpenAI API error for chunk #{index}: #{inspect(error)}")
            {:halt, {:error, error}}
        end
      end)

    partial_summaries
  end

  defp generate_final_summary(partial_summaries) do
    Logger.info("Generating final summary from #{length(partial_summaries)} partial summaries")

    # Combine all partial summaries
    combined_summaries = Enum.join(partial_summaries, "\n\n---\n\n")

    final_prompt = """
    You are analyzing multiple executive summaries from different batches of customer support call transcripts.

    Your task:
    - Read all the partial executive summaries below carefully.
    - Generate a comprehensive final executive summary in markdown format that:
      - Synthesizes information from all partial summaries
      - Identifies overall patterns and trends across all calls
      - Highlights the most critical issues and insights
      - Provides a unified view of call volume, customer issues, service quality, and performance
      - Includes actionable recommendations and follow-up items

    Return the result as a well-structured markdown document with appropriate headings, bullet points, and formatting.

    Partial summaries:
    #{combined_summaries}
    """

    messages = [%{"role" => "user", "content" => final_prompt}]

    case OpenAI.chat_completion(messages, 0, "gpt-4.1") do
      {:ok, response_content} ->
        {:ok, response_content}

      {:error, error} ->
        Logger.error("OpenAI API error for final summary: #{inspect(error)}")
        {:error, error}
    end
  end

  defp save_daily_summary(summary_content, org_id) do
    # Generate a unique ID for the daily summary
    daily_summary_id = Ecto.UUID.generate()

    # Get current date in UTC (start of day)
    today_date = DateTime.utc_now() |> DateTime.to_date()
    today_start = DateTime.new!(today_date, ~T[00:00:00], "Etc/UTC")
    today_end = DateTime.new!(Date.add(today_date, 1), ~T[00:00:00], "Etc/UTC")

    # Count promises created today
    total_promises_created =
      from(p in Promises,
        where: p.org_id == ^org_id,
        where: p.created_at >= ^today_start and p.created_at < ^today_end,
        select: count(p.id)
      )
      |> Repo.one()

    # Count all promises closed (status is CLOSED, regardless of when they were closed)
    total_promises_closed =
      from(p in Promises,
        where: p.org_id == ^org_id,
        where: p.status == "CLOSED",
        select: count(p.id)
      )
      |> Repo.one()

    # Prepare the attributes for the DailySummary changeset
    attrs = %{
      id: daily_summary_id,
      org_id: org_id,
      date: today_start,
      executive_summary: summary_content,
      total_promises_created: total_promises_created || 0,
      total_promises_closed: total_promises_closed || 0
    }

    # Insert the daily summary
    # Note: Uniqueness is already checked in run_daily_summary_for_org before generating
    case Repo.insert(DailySummary.changeset(%DailySummary{}, attrs)) do
      {:ok, daily_summary} ->
        Logger.info(
          "Daily summary saved successfully with ID: #{daily_summary.id}, promises created: #{total_promises_created || 0}, promises closed: #{total_promises_closed || 0}"
        )

        {:ok, daily_summary}

      {:error, changeset} ->
        Logger.error("Failed to save daily summary: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  # Count tokens using word count multiplied by 1.3
  defp count_tokens(text) when is_binary(text) do
    word_count = count_words(text)
    round(word_count * 1.3)
  end

  defp count_tokens(_), do: 0

  # Count words in the text string
  defp count_words(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  @doc """
  Fallback function to check all organizations with daily summary enabled
  and generate missing summaries for the last 23 hours (excluding current hour).
  """
  def fallback_daily_summaries do
    Logger.info("Fallback daily summary job started")

    now_utc = DateTime.utc_now()

    # Get start of previous hour (excluding current hour)
    # If it's 2:30 PM, we want to check up to 1:00 PM (start of previous hour)
    %DateTime{} = previous_hour = DateTime.add(now_utc, -1, :hour)

    start_of_previous_hour = %DateTime{
      previous_hour
      | minute: 0,
        second: 0,
        microsecond: {0, 6}
    }

    # Calculate 23 hours before the start of previous hour
    # This gives us a 23-hour window ending at the start of previous hour
    twenty_three_hours_ago =
      start_of_previous_hour
      |> DateTime.add(-23, :hour)

    Logger.info(
      "Checking for missing daily summaries between #{DateTime.to_iso8601(twenty_three_hours_ago)} and #{DateTime.to_iso8601(start_of_previous_hour)} (excluding current hour)"
    )

    # Get all organizations with daily summary enabled
    orgs_with_daily_summary = Org.get_orgs_with_daily_summary_enabled()

    Logger.info(
      "Found #{length(orgs_with_daily_summary)} organizations with daily summary enabled"
    )

    # Process each organization
    results =
      Enum.map(orgs_with_daily_summary, fn org ->
        check_and_generate_missing_summaries(org, twenty_three_hours_ago, start_of_previous_hour)
      end)

    success_count = Enum.count(results, fn r -> r == :ok end)
    error_count = Enum.count(results, fn r -> r == :error end)

    Logger.info(
      "Fallback daily summary job completed. Success: #{success_count}, Errors: #{error_count}"
    )

    {:ok, :processed}
  rescue
    error ->
      Logger.error("Fallback daily summary job failed: #{inspect(error)}")
      {:error, error}
  end

  defp check_and_generate_missing_summaries(org, start_time, end_time) do
    # Get current time in org's timezone
    timezone = org.daily_summary_time_zone

    case DateTime.now(timezone) do
      {:ok, org_now} ->
        # Get today's date in org's timezone
        org_today = DateTime.to_date(org_now)
        org_today_start = DateTime.new!(org_today, ~T[00:00:00], timezone)
        org_today_end = DateTime.new!(Date.add(org_today, 1), ~T[00:00:00], timezone)

        # Convert to UTC for database comparison
        org_today_start_utc = DateTime.shift_zone!(org_today_start, "Etc/UTC")
        org_today_end_utc = DateTime.shift_zone!(org_today_end, "Etc/UTC")

        # Check if the org's today falls within the 23-hour window (excluding current hour)
        # The window should overlap with the org's today date range
        today_in_range =
          DateTime.compare(org_today_start_utc, end_time) == :lt and
            DateTime.compare(org_today_end_utc, start_time) == :gt

        if today_in_range do
          Logger.info(
            "Org #{org.subdomain} today (local date: #{Date.to_string(org_today)}) falls within the checked time range. Attempting to generate summary..."
          )

          # Attempt to generate today's summary
          # run_daily_summary_for_org will check if it already exists before generating
          run_daily_summary_for_org(org)
        else
          Logger.info(
            "Today (local date: #{Date.to_string(org_today)}) is not in the checked time range (last 23 hours) for org #{org.subdomain}. Skipping."
          )

          :ok
        end

      {:error, error} ->
        Logger.error(
          "Error getting current time in timezone #{timezone} for org #{org.subdomain}: #{inspect(error)}"
        )

        :error
    end
  rescue
    error ->
      Logger.error(
        "Error checking/generating summaries for org #{org.subdomain}: #{inspect(error)}"
      )

      :error
  end

  defp has_daily_summary_for_date?(org_id, date) do
    # Convert date to start of day datetime for comparison
    date_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

    case Repo.one(
           from(ds in DailySummary,
             where: ds.org_id == ^org_id,
             where: fragment("DATE(?) = DATE(?)", ds.date, ^date_start),
             limit: 1,
             select: 1
           )
         ) do
      nil -> false
      _ -> true
    end
  end
end
