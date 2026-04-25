defmodule Comcent.NewCallStoryProcessor do
  require Logger

  alias Comcent.Schemas.{
    CallTranscript,
    CallStory,
    CallSpan,
    CallAnalysis,
    Promises,
    DailySummary
  }

  alias Comcent.Repo.Org
  alias Comcent.{Repo, Plans, Charges, S3, Deepgram, VCon, WebhookPusher, Search}
  alias Comcent.Repo.DailySummary, as: DailySummaryRepo
  alias Comcent.Search

  def new_call_story_processor(%{type: "NEW_CALL_STORY", data: %{call_story_id: call_story_id}}) do
    case Repo.get(CallStory, call_story_id)
         |> Repo.preload([:call_spans, :call_transcripts, :call_analyses, :org, org: :webhooks]) do
      nil ->
        Logger.error("Call story not found for id #{call_story_id}")
        :error

      call_story ->
        org = call_story.org
        process_call_story(call_story, org)
    end
  end

  defp process_call_story(call_story, org) do
    with :ok <- Charges.charge_for_call_minutes(call_story),
         :ok <- Charges.update_storage_used_for_call_recordings(call_story) do
      if org.is_active && org.wallet_balance >= 0 do
        process_active_org_call(call_story, org)
      else
        Logger.error("Looks like either the org is not active or the wallet balance is low")
        :ok
      end
    end
  end

  defp process_active_org_call(call_story, org) do
    if org.enable_transcription do
      with {:ok, transcriptions} <-
             generate_transcript_and_save(call_story, org.enable_sentiment_analysis),
           # Reload call_story to get the newly saved transcripts
           reloaded_call_story <-
             Repo.get(CallStory, call_story.id)
             |> Repo.preload([
               :call_spans,
               :call_transcripts,
               :call_analyses,
               :org,
               org: :webhooks
             ]),
           {:ok, transcript_text} <-
             Comcent.Transcript.create_transcript_text(reloaded_call_story) do
        if org.enable_summary do
          generate_and_save_summary(call_story, transcript_text, transcriptions)
        end

        agent_transcript = extract_agent_transcript(transcript_text)
        Logger.info("Agent transcript: #{inspect(agent_transcript)}")
        generate_and_save_promise(call_story, agent_transcript)

        with vcon <- VCon.generate_vcon(reloaded_call_story) do
          WebhookPusher.push_to_webhook(reloaded_call_story, vcon)
        end

        if org.enable_labels do
          generate_and_save_labels(org, call_story, transcript_text)
        end

        Logger.info("transcript text: #{inspect(transcript_text)}")
      end
    else
      with vcon <- VCon.generate_vcon(call_story) do
        WebhookPusher.push_to_webhook(call_story, vcon)
      end
    end
  end

  defp extract_agent_transcript(transcript_text) do
    domain = Application.fetch_env!(:comcent, :sip_user_root_domain)

    transcript_text
    |> String.split("\n\n")
    |> Enum.filter(&String.contains?(&1, "#{domain}:"))
    |> Enum.join("\n\n")
  end

  defp generate_and_save_promise(call_story, agent_transcript) do
    case generate_promise(agent_transcript) do
      {:ok, promises} when is_list(promises) and length(promises) > 0 ->
        Logger.info("Promises found for call_story #{call_story.id}: #{inspect(promises)}")

        save_promises(call_story, promises)

      {:ok, []} ->
        Logger.info("No promises found for call_story #{call_story.id}")
        :ok

      {:error, error} ->
        Logger.error(
          "Failed to generate promises for call_story #{call_story.id}: #{inspect(error)}"
        )

        :error
    end
  end

  defp generate_promise(agent_transcript) do
    today = DateTime.utc_now() |> DateTime.to_iso8601()

    prompt = """
    Today's date and time is: #{today}

    From the below text, extract all promises made in the call.

    Each promise should include only:
    - "agent": the agent's username
    - "promise": short description of what was promised to be done
    - "time": when it will be done converted to ISO 8601 datetime format (if mentioned, else null). Use today's date as reference to calculate the exact datetime.

    Important: Convert relative time references (like "tomorrow", "next week", "in 2 days") to ISO 8601 datetime format based on today's date.
    For times without a specific date (like "5 PM"), assume it's today if the time hasn't passed, otherwise tomorrow.

    Return the output strictly as a JSON array, like this:
    [
      {
        "agent": "jane@acme.example.com",
        "promise": "call back",
        "time": "2025-10-16T09:00:00Z"
      },
      {
        "agent": "john@acme.example.com",
        "promise": "send invoice",
        "time": "2025-10-15T17:00:00Z"
      }
    ]

    Text:
    #{agent_transcript}
    """

    messages = [
      %{
        "role" => "user",
        "content" => prompt
      }
    ]

    case Comcent.OpenAI.chat_completion(messages) do
      {:ok, content} ->
        # Strip markdown code block formatting if present
        cleaned_content =
          content
          |> String.trim()
          |> String.replace(~r/^```json\s*/m, "")
          |> String.replace(~r/\s*```$/m, "")
          |> String.trim()

        # Try to parse JSON response
        case Jason.decode(cleaned_content) do
          {:ok, promises} when is_list(promises) ->
            {:ok, promises}

          {:ok, _} ->
            Logger.warning("OpenAI returned non-array response: #{inspect(cleaned_content)}")
            {:ok, []}

          {:error, _} ->
            # If JSON parsing fails, return the raw content
            Logger.warning("Failed to parse OpenAI response as JSON: #{inspect(cleaned_content)}")
            {:ok, []}
        end

      {:error, error} ->
        Logger.error("OpenAI API call failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp save_promises(call_story, promises) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    today_date = now |> DateTime.to_date()
    today_start = DateTime.new!(today_date, ~T[00:00:00], "Etc/UTC")

    Repo.transaction(fn ->
      # Count successfully inserted promises
      promises_count =
        Enum.reduce(promises, 0, fn promise_data, acc ->
          try do
            due_date = parse_due_date(promise_data["time"])

            # Extract username from email (e.g., "kotappa@acme.example.com" -> "kotappa")
            agent = promise_data["agent"] || ""
            username = agent |> String.split("@") |> List.first() || ""

            %Promises{
              id: Ecto.UUID.generate(),
              promise: promise_data["promise"],
              status: "OPEN",
              created_by: username,
              assigned_to: username,
              due_date: due_date,
              org_id: call_story.org_id,
              call_story_id: call_story.id,
              created_at: now,
              updated_at: now
            }
            |> Repo.insert!()

            Logger.info(
              "Saved promise: #{promise_data["promise"]} for agent: #{promise_data["agent"]}"
            )

            acc + 1
          rescue
            error ->
              Logger.error(
                "Failed to save promise: #{inspect(promise_data)}, error: #{inspect(error)}"
              )

              acc
          end
        end)

      # Check if daily summary exists for today and update total_promises_created
      if promises_count > 0 do
        update_daily_summary_promise_count(call_story.org_id, today_start, promises_count)
      end
    end)

    :ok
  end

  defp update_daily_summary_promise_count(org_id, date, promises_count) do
    case DailySummaryRepo.get_daily_summary_by_date_and_org_id(org_id, date) do
      nil ->
        Logger.debug("No daily summary found for today, skipping promise count update")

      daily_summary ->
        updated_count = (daily_summary.total_promises_created || 0) + promises_count

        DailySummary.changeset(daily_summary, %{
          total_promises_created: updated_count
        })
        |> Repo.update!()

        Logger.info(
          "Updated daily summary #{daily_summary.id} with #{promises_count} new promises. New total: #{updated_count}"
        )
    end
  end

  defp parse_due_date(nil), do: nil

  defp parse_due_date(time_string) do
    case DateTime.from_iso8601(time_string) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _} -> nil
    end
  end

  defp generate_and_save_labels(org, call_story, transcript_text) do
    labels = org.labels

    cond do
      is_nil(labels) ->
        Logger.info(
          "Skipping label generation for call_story #{call_story.id} - No labels configured"
        )

        :ok

      labels == [] ->
        Logger.info(
          "Skipping label generation for call_story #{call_story.id} - Empty labels array"
        )

        :ok

      true ->
        case generate_labels(labels, transcript_text) do
          {:ok, assigned_labels} ->
            with :ok <- save_labels(call_story, assigned_labels) do
              :ok
            end

          {:error, error} ->
            Logger.error(
              "Failed to generate labels for call_story #{call_story.id}: #{inspect(error)}"
            )

            :error
        end
    end
  end

  defp generate_labels(labels, transcript_text) do
    # Build the labels description for the prompt
    labels_description =
      labels
      |> Enum.map(fn label ->
        "- #{label["name"]}: #{label["description"]}"
      end)
      |> Enum.join("\n")

    prompt = """
    You are a conversation labeling assistant.
    Read the transcript between an agent and a customer and assign all relevant labels from the list below.

    Labels:
    #{labels_description}

    Transcript:
    #{transcript_text}

    Return your answer as a JSON array of label names (strings only). Do not use markdown formatting.
    Example: ["label1", "label2"]
    If no labels apply, return an empty array: []
    """

    messages = [
      %{
        "role" => "user",
        "content" => prompt
      }
    ]

    case Comcent.OpenAI.chat_completion(messages, 0) do
      {:ok, response} ->
        # Strip markdown code blocks if present
        cleaned_response = strip_markdown_code_blocks(response)

        case Jason.decode(cleaned_response) do
          {:ok, assigned_labels} when is_list(assigned_labels) ->
            Logger.info("Assigned labels: #{inspect(assigned_labels)}")
            {:ok, assigned_labels}

          {:ok, _} ->
            Logger.error("Invalid response format from OpenAI: #{inspect(response)}")
            {:error, :invalid_response_format}

          {:error, error} ->
            Logger.error("Failed to parse OpenAI response: #{inspect(error)}")
            {:error, error}
        end

      {:error, error} ->
        Logger.error("OpenAI API error: #{inspect(error)}")
        {:error, error}
    end
  end

  defp strip_markdown_code_blocks(text) do
    text
    |> String.trim()
    |> String.replace(~r/^```json\s*/, "")
    |> String.replace(~r/^```\s*/, "")
    |> String.replace(~r/\s*```$/, "")
    |> String.trim()
  end

  defp save_labels(call_story, assigned_labels) do
    call_story
    |> Ecto.Changeset.change(%{labels: assigned_labels, is_labeled: true})
    |> Repo.update()
    |> case do
      {:ok, _updated_call_story} ->
        Logger.info(
          "Labels saved successfully for call_story #{call_story.id}: #{inspect(assigned_labels)}"
        )

        :ok

      {:error, changeset} ->
        Logger.error(
          "Failed to save labels for call_story #{call_story.id}: #{inspect(changeset)}"
        )

        :error
    end
  end

  defp generate_transcript_and_save(call_story, enable_sentiment) do
    with {:ok, transcriptions} <- generate_transcript(call_story, enable_sentiment),
         :ok <- save_transcription(call_story, transcriptions),
         :ok <- calculate_and_charge_for_transcription(call_story, transcriptions) do
      if enable_sentiment do
        with :ok <- save_sentiment_data(call_story, transcriptions),
             :ok <- calculate_and_charge_for_sentiment(call_story, transcriptions) do
          Search.search_index_the_call_story(call_story, transcriptions)
          {:ok, transcriptions}
        end
      else
        Search.search_index_the_call_story(call_story, transcriptions)
        {:ok, transcriptions}
      end
    else
      {:error, :no_transcriptions} ->
        Logger.info(
          "Skipping transcription processing for call_story #{call_story.id} as no transcriptions were generated"
        )

        {:ok, []}

      error ->
        Logger.error("Error in generate_transcript_and_save: #{inspect(error)}")
        error
    end
  end

  defp generate_transcript(call_story, enable_sentiment) do
    Logger.info("Generating transcript for call_story #{call_story.id}")

    transcriptions =
      call_story.call_spans
      |> Enum.filter(&(&1.type == "RECORDING" && &1.metadata["direction"] == "in"))
      |> Enum.map(fn span ->
        Task.async(fn ->
          try do
            file_name = get_in(span.metadata, ["file_name"])

            if is_nil(file_name) or file_name == "" do
              Logger.error("Missing or empty file_name in span metadata: #{inspect(span)}")
              nil
            else
              url =
                S3.get_recording_pre_signed_url(call_story.org.subdomain, file_name)

              case Deepgram.transcribe_url(url, enable_sentiment) do
                {:ok, result} ->
                  %{
                    call_story_id: call_story.id,
                    recording_span_id: span.id,
                    current_party: span.current_party,
                    provider: "DEEPGRAM",
                    transcript_data: result
                  }

                {:error, error} ->
                  Logger.error("Deepgram API error for span #{span.id}: #{inspect(error)}")
                  Logger.error("Failed to transcribe recording file: #{file_name}")
                  Logger.error("URL used: #{url}")
                  nil
              end
            end
          rescue
            error ->
              Logger.error("Error while transcribing span #{span.id}: #{inspect(error)}")
              Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
              nil
          end
        end)
      end)
      |> Enum.map(&Task.await(&1, 130_000))
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(transcriptions) do
      Logger.error("No transcriptions were generated for call_story #{call_story.id}")
      {:error, :no_transcriptions}
    else
      {:ok, transcriptions}
    end
  end

  defp get_total_duration(transcriptions) do
    Enum.reduce(transcriptions, 0, fn ts, acc ->
      duration = get_in(ts, [:transcript_data, "metadata", "duration"])
      acc + duration
    end)
  end

  defp calculate_and_charge_for_transcription(call_story, transcriptions) do
    total_duration = get_total_duration(transcriptions)

    minutes = ceil(total_duration / 60)
    price = Plans.active().prices.transcription * minutes
    cost = Plans.active().costs.transcription * minutes

    try do
      case Org.charge_org_wallet_by_org_id(
             call_story.org_id,
             price,
             "CALL_TRANSCRIPTION",
             call_story.id,
             minutes,
             cost
           ) do
        :ok ->
          :ok

        :error ->
          Logger.error("Failed to charge for transcription")
          :error
      end
    rescue
      error ->
        Logger.error("Error while charging for transcription of call_story_id: #{call_story.id}",
          error: error,
          error_type: error.__struct__,
          error_message: Exception.message(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__),
          price: price,
          cost: cost,
          minutes: minutes,
          org_id: call_story.org_id,
          transcriptions: inspect(transcriptions)
        )

        :error
    end
  end

  defp calculate_and_charge_for_sentiment(call_story, transcriptions) do
    total_duration = get_total_duration(transcriptions)
    minutes = ceil(total_duration / 60)

    price = Plans.active().prices.sentiment_analysis * minutes

    {input_tokens, output_tokens} =
      Enum.reduce(transcriptions, {0, 0}, fn ts, {input_acc, output_acc} ->
        sentiment_info = get_in(ts, [:transcript_data, "metadata", "sentiment_info"])

        if sentiment_info do
          {
            input_acc + (sentiment_info["input_tokens"] || 0),
            output_acc + (sentiment_info["output_tokens"] || 0)
          }
        else
          Logger.warning("No sentiment info found in transcription: #{inspect(ts)}")
          {input_acc, output_acc}
        end
      end)

    input_token_cost = Plans.active().costs.audio_intelligence_input * input_tokens
    output_token_cost = Plans.active().costs.audio_intelligence_output * output_tokens
    cost = input_token_cost + output_token_cost

    try do
      with :ok <-
             Org.charge_org_wallet_by_org_id(
               call_story.org_id,
               price,
               "CALL_SENTIMENT_ANALYSIS",
               call_story.id,
               minutes,
               cost
             ) do
        :ok
      end
    rescue
      error ->
        Logger.error(
          "Error while charging for sentiment analysis of call_story_id: #{call_story.id}",
          error: error,
          error_type: error.__struct__,
          error_message: Exception.message(error),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__),
          price: price,
          cost: cost,
          minutes: minutes,
          org_id: call_story.org_id,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          input_token_cost: input_token_cost,
          output_token_cost: output_token_cost
        )

        :error
    end
  end

  defp save_transcription(call_story, transcriptions) do
    Repo.transaction(fn ->
      Enum.each(transcriptions, fn transcription ->
        case transcription.transcript_data do
          %{"results" => _} = data ->
            Repo.insert!(%CallTranscript{
              id: Ecto.UUID.generate(),
              call_story_id: transcription.call_story_id,
              recording_span_id: transcription.recording_span_id,
              current_party: transcription.current_party,
              provider: transcription.provider,
              transcript_data: data
            })

          _ ->
            Logger.error(
              "Invalid transcript data format: #{inspect(transcription.transcript_data)}"
            )
        end
      end)

      call_story
      |> Ecto.Changeset.change(%{is_transcribed: true})
      |> Repo.update!()
    end)

    :ok
  end

  defp save_sentiment_data(call_story, transcriptions) do
    Repo.transaction(fn ->
      Enum.each(transcriptions, fn transcription ->
        sentiment_data =
          get_in(transcription.transcript_data, ["results", "sentiments", "average", "sentiment"])

        if sentiment_data do
          case Repo.get(CallSpan, transcription.recording_span_id) do
            nil ->
              Logger.error("Failed to find CallSpan with id: #{transcription.recording_span_id}")
              :error

            span ->
              case Repo.update(
                     Ecto.Changeset.change(span, %{
                       metadata: Map.put(span.metadata || %{}, "sentiment", sentiment_data)
                     })
                   ) do
                {:ok, _updated} ->
                  :ok

                {:error, error} ->
                  Logger.error("Error updating CallSpan metadata: #{inspect(error)}")
                  :error
              end
          end
        else
          Logger.warning("No sentiment data found for transcription: #{inspect(transcription)}")
        end
      end)

      call_story
      |> Ecto.Changeset.change(%{is_sentiment_analyzed: true})
      |> Repo.update!()
    end)

    :ok
  end

  defp generate_and_save_summary(call_story, transcript_text, transcriptions) do
    case transcript_text do
      {:ok, text} when is_binary(text) and text != "" ->
        case generate_summary(text) do
          {:ok, summary} ->
            with :ok <- save_summary(call_story, summary) do
              calculate_and_charge_for_summary(call_story, summary, transcriptions)
            end

          {:error, error} ->
            Logger.error(
              "Failed to generate summary for call_story #{call_story.id}: #{inspect(error)}"
            )

            :error
        end

      {:ok, ""} ->
        Logger.info(
          "Skipping summary generation for call_story #{call_story.id} - Empty transcript"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "Error getting transcript text for call_story #{call_story.id}: #{inspect(reason)}"
        )

        :error

      text when is_binary(text) and text != "" ->
        case generate_summary(text) do
          {:ok, summary} ->
            with :ok <- save_summary(call_story, summary) do
              calculate_and_charge_for_summary(call_story, summary, transcriptions)
            end

          {:error, error} ->
            Logger.error(
              "Failed to generate summary for call_story #{call_story.id}: #{inspect(error)}"
            )

            :error
        end

      text when is_binary(text) ->
        Logger.info(
          "Skipping summary generation for call_story #{call_story.id} - Empty transcript"
        )

        :ok

      error ->
        Logger.error(
          "Unexpected error getting transcript text for call_story #{call_story.id}: #{inspect(error)}"
        )

        :error
    end
  end

  defp generate_summary(text) do
    case Deepgram.generate_summary(text) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        Logger.error("Failed to generate summary: #{inspect(error)}")
        {:error, error}
    end
  end

  defp save_summary(call_story, summary) do
    Repo.transaction(fn ->
      Repo.insert!(%CallAnalysis{
        id: Ecto.UUID.generate(),
        call_story_id: call_story.id,
        provider: "DEEPGRAM",
        type: "SUMMARY",
        analysis_data: summary
      })

      call_story
      |> Ecto.Changeset.change(%{is_summarized: true})
      |> Repo.update!()
    end)

    :ok
  end

  defp calculate_and_charge_for_summary(call_story, summary, transcriptions) do
    total_duration = get_total_duration(transcriptions)
    minutes = ceil(total_duration / 60)
    price = Plans.active().prices.summary * minutes
    input_tokens = get_in(summary, ["metadata", "summary_info", "input_tokens"])
    output_tokens = get_in(summary, ["metadata", "summary_info", "output_tokens"])
    input_token_cost = Plans.active().costs.audio_intelligence_input * input_tokens
    output_token_cost = Plans.active().costs.audio_intelligence_output * output_tokens
    cost = input_token_cost + output_token_cost

    try do
      with :ok <-
             Org.charge_org_wallet_by_org_id(
               call_story.org_id,
               price,
               "CALL_SUMMARY_ANALYSIS",
               call_story.id,
               minutes,
               cost
             ) do
        :ok
      end
    rescue
      error ->
        Logger.error("Error while charging for summary of call_story_id: #{call_story.id}",
          error: error,
          price: price,
          cost: cost,
          minutes: minutes,
          org_id: call_story.org_id,
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          input_token_cost: input_token_cost,
          output_token_cost: output_token_cost
        )

        :error
    end
  end
end
