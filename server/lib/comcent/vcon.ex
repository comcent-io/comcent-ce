defmodule Comcent.VCon do
  alias Comcent.Schemas.{CallSpan, OrgMember, CallTranscript, CallAnalysis}
  alias Comcent.Types.{VCon, CallStoryAssociation}
  alias Comcent.S3
  alias Comcent.Transcript
  alias Comcent.Repo
  import Ecto.Query
  require Logger

  @spec generate_vcon(CallStoryAssociation.t()) :: VCon.t()
  def generate_vcon(call_story) do
    parties = get_parties(call_story)
    attachments = get_attachments(call_story)
    dialog = get_dialog(call_story, parties)
    analysis = get_analysis(call_story)

    %{
      vcon: "0.0.1",
      uuid: call_story.id,
      created_at: call_story.start_at,
      parties: parties,
      dialog: dialog,
      attachments: attachments,
      analysis: analysis
    }
  end

  @spec get_parties(CallStoryAssociation.t()) :: [VCon.party()]
  defp get_parties(call_story) do
    try do
      # Check if call_spans exists and is not nil
      if is_nil(call_story.call_spans) do
        Logger.error("call_spans is nil for call_story #{call_story.id}")
        []
      else
        all_party = Enum.map(call_story.call_spans, & &1.current_party)

        # Check if caller and callee exist
        if is_nil(call_story.caller) or is_nil(call_story.callee) do
          Logger.error(
            "Caller or callee is nil for call_story #{call_story.id}. Caller: #{inspect(call_story.caller)}, Callee: #{inspect(call_story.callee)}"
          )
        end

        unique_parties = Enum.uniq(all_party)
        first_party = call_story.caller
        second_party = call_story.callee
        other_parties = Enum.reject(unique_parties, &(&1 == first_party or &1 == second_party))
        all_parties = [first_party, second_party | other_parties]

        processed_parties =
          Enum.map(all_parties, fn party ->
            try do
              result =
                case party do
                  nil ->
                    Logger.error("Found nil party in all_parties")
                    %{tel: "unknown"}

                  party when is_binary(party) ->
                    if String.contains?(party, "@") do
                      case String.split(party, "@") do
                        [username, domain] ->
                          # Extract subdomain from the domain
                          subdomain =
                            case String.split(domain, ".") do
                              [subdomain, "comcent", "io"] ->
                                subdomain

                              _ ->
                                Logger.error("Invalid domain format: #{domain}")
                                nil
                            end

                          if subdomain do
                            try do
                              case Comcent.Repo.one(
                                     from o in OrgMember,
                                       where:
                                         o.org_id == ^call_story.org_id and
                                           o.username == ^username,
                                       preload: :user
                                   ) do
                                nil ->
                                  %{tel: party}

                                member ->
                                  %{
                                    tel: party,
                                    mailto: member.user.email,
                                    name: member.user.name
                                  }
                              end
                            rescue
                              e ->
                                Logger.error("Error looking up OrgMember: #{inspect(e)}")
                                %{tel: party}
                            end
                          else
                            %{tel: party}
                          end

                        _ ->
                          Logger.error("Invalid party format (multiple @ symbols): #{party}")
                          %{tel: party}
                      end
                    else
                      %{tel: party}
                    end

                  _ ->
                    Logger.error("Invalid party type: #{inspect(party)}")
                    %{tel: "invalid"}
                end

              result
            rescue
              e ->
                Logger.error("Error processing party #{inspect(party)}: #{inspect(e)}")
                %{tel: "error"}
            end
          end)

        processed_parties
      end
    rescue
      e ->
        Logger.error("Error in get_parties: #{inspect(e)}")
        []
    end
  end

  @spec get_disposition(CallSpan.t() | nil, CallSpan.t() | nil) :: VCon.dialog_disposition() | nil
  defp get_disposition(callee_span, caller_span) do
    callee_answer_state = get_in(callee_span, [:metadata, "answerState"])
    caller_answer_state = get_in(caller_span, [:metadata, "answerState"])

    if callee_answer_state == "hangup" or caller_answer_state == "hangup" do
      if callee_answer_state == "hangup" do
        hangup_cause = get_in(callee_span, [:metadata, "hangupCause"])

        case hangup_cause do
          "NO_ANSWER" -> :"no-answer"
          "USER_BUSY" -> :busy
          "NO_USER_RESPONSE" -> :"hung-up"
          "SWITCH_CONGESTION" -> :congestion
          _ -> :"hung-up"
        end
      end
    end
  end

  @spec get_dialog(CallStoryAssociation.t(), [VCon.party()]) :: [VCon.dialog()]
  defp get_dialog(call_story, parties) do
    try do
      recording_span =
        Enum.filter(call_story.call_spans, fn s ->
          s.type == "RECORDING" and s.metadata["direction"] == "both"
        end)

      cond do
        Enum.empty?(recording_span) ->
          callee_span = Enum.find(call_story.call_spans, &(&1.type == "RINGING"))
          caller_span = Enum.find(call_story.call_spans, &(&1.type == "DIAL_WAIT"))

          if is_nil(caller_span) do
            Logger.error("No caller span found for call_story #{call_story.id}")
            []
          else
            caller_index = Enum.find_index(parties, &(&1.tel == call_story.caller))
            callee_index = Enum.find_index(parties, &(&1.tel == call_story.callee))

            disposition =
              if callee_span != nil and caller_span != nil do
                get_disposition(callee_span, caller_span)
              end

            [
              %{
                type: :incomplete,
                start: caller_span.start_at,
                duration: DateTime.diff(call_story.end_at, caller_span.start_at),
                parties: [caller_index, callee_index],
                disposition: disposition
              }
            ]
          end

        length(recording_span) == 2 ->
          caller_span = Enum.find(recording_span, &(&1.current_party == call_story.caller))

          if is_nil(caller_span) do
            Logger.error(
              "No caller span found in recording spans for call_story #{call_story.id}"
            )

            []
          else
            caller_index = Enum.find_index(parties, &(&1.tel == call_story.caller))
            callee_index = Enum.find_index(parties, &(&1.tel == call_story.callee))

            try do
              metadata = caller_span.metadata

              url =
                S3.get_recording_pre_signed_url(call_story.org.subdomain, metadata["file_name"])

              [
                %{
                  type: :recording,
                  start: caller_span.start_at,
                  duration: DateTime.diff(call_story.end_at, caller_span.start_at),
                  parties: [caller_index, callee_index],
                  mimetype: :"audio/x-wav",
                  filename: metadata["file_name"],
                  url: url,
                  alg: "SHA-512",
                  signature: metadata["sha512"]
                }
              ]
            rescue
              e ->
                Logger.error("Error processing recording span: #{inspect(e)}")
                []
            end
          end

        length(recording_span) > 2 ->
          customer_span =
            if call_story.direction == "inbound" do
              Enum.find(recording_span, &(&1.current_party == call_story.caller))
            else
              Enum.find(recording_span, &(&1.current_party == call_story.callee))
            end

          if is_nil(customer_span) do
            Logger.error("No customer span found for call_story #{call_story.id}")
            []
          else
            other_spans =
              Enum.reject(recording_span, &(&1.current_party == customer_span.current_party))

            customer_index = Enum.find_index(parties, &(&1.tel == customer_span.current_party))
            originator_index = Enum.find_index(parties, &(&1.tel == call_story.caller))

            temp_dialog =
              Enum.map(other_spans, fn span ->
                try do
                  agent_index = Enum.find_index(parties, &(&1.tel == span.current_party))
                  metadata = span.metadata

                  url =
                    S3.get_recording_pre_signed_url(
                      call_story.org.subdomain,
                      metadata["file_name"]
                    )

                  %{
                    type: :recording,
                    start: span.start_at,
                    duration: DateTime.diff(call_story.end_at, span.start_at),
                    parties: [customer_index, agent_index],
                    originator: originator_index,
                    mimetype: :"audio/x-wav",
                    filename: metadata["file_name"],
                    url: url,
                    alg: "SHA-512",
                    signature: metadata["sha512"]
                  }
                rescue
                  e ->
                    Logger.error("Error processing span: #{inspect(e)}")
                    nil
                end
              end)
              |> Enum.reject(&is_nil/1)

            if Enum.empty?(temp_dialog) do
              []
            else
              dialog = [hd(temp_dialog)]

              Enum.reduce(1..(length(temp_dialog) - 1), dialog, fn i, acc ->
                prev_dialog = Enum.at(temp_dialog, i - 1)
                next_dialog = Enum.at(temp_dialog, i)
                transferor = List.first(prev_dialog.parties -- next_dialog.parties)
                transferee = List.first(prev_dialog.parties -- [transferor])
                transfer_target = List.first(next_dialog.parties -- prev_dialog.parties)

                transfer_dialog = %{
                  type: :transfer,
                  transferor: transferor,
                  transferee: transferee,
                  transferTarget: transfer_target,
                  original: i - 1,
                  targetDialog: i
                }

                acc ++ [transfer_dialog, next_dialog]
              end)
            end
          end
      end
    rescue
      e ->
        Logger.error("Error in get_dialog: #{inspect(e)}")
        []
    end
  end

  @spec get_attachments(CallStoryAssociation.t()) :: [VCon.attachment()]
  defp get_attachments(call_story) do
    sorted_span = Enum.sort_by(call_story.call_spans, & &1.start_at)

    group_by_channel_id = Enum.group_by(sorted_span, & &1.channel_id)

    legs =
      Enum.map(group_by_channel_id, fn {channel_id, spans} ->
        %{
          channel_id: channel_id,
          party: hd(spans).current_party,
          call_spans: spans
        }
      end)

    # Create a map with only the fields we want to encode
    call_story_export = %{
      id: call_story.id,
      start_at: call_story.start_at,
      end_at: call_story.end_at,
      caller: call_story.caller,
      callee: call_story.callee,
      outbound_caller_id: call_story.outbound_caller_id,
      direction: call_story.direction,
      is_transcribed: call_story.is_transcribed,
      is_summarized: call_story.is_summarized,
      is_sentiment_analyzed: call_story.is_sentiment_analyzed,
      is_anonymized: call_story.is_anonymized,
      hangup_party: call_story.hangup_party,
      org_id: call_story.org_id,
      legs: legs
    }

    [
      %{
        party: 0,
        type: "comcent.call_story",
        body:
          case Jason.encode(call_story_export) do
            {:ok, encoded} -> encoded
            {:error, _} -> "{}"
          end,
        encoding: "json"
      }
    ]
  end

  @spec get_analysis(CallStoryAssociation.t()) :: [VCon.analysis()]
  defp get_analysis(call_story) do
    try do
      analysis = []

      call_transcripts =
        try do
          Repo.all(
            from t in CallTranscript,
              where: t.call_story_id == ^call_story.id,
              select: %{
                id: t.id,
                recording_span_id: t.recording_span_id,
                current_party: t.current_party,
                provider: t.provider,
                transcript_data: t.transcript_data,
                call_story_id: t.call_story_id
              }
          )
        rescue
          e ->
            Logger.error("Error fetching call transcripts: #{inspect(e)}")
            []
        end

      if length(call_transcripts) > 0 do
        try do
          call_story_copy = Map.put(call_story, :call_transcripts, call_transcripts)
          transcript_chat = Transcript.create_transcript_chat(call_story_copy)

          transcription = %{
            type: "transcription",
            vendor: "comcent",
            schema: "comcent.deepgram.nova2.v1",
            body:
              case Jason.encode(transcript_chat) do
                {:ok, encoded} -> encoded
                {:error, _} -> "{}"
              end,
            encoding: "json"
          }

          if get_in(hd(call_transcripts), [:transcript_data, "results", "sentiments"]) do
            sentiments =
              Enum.map(call_transcripts, fn t ->
                transcript_data = t.transcript_data

                %{
                  current_party: t.current_party,
                  sentiment:
                    get_in(transcript_data, ["results", "sentiments", "average", "sentiment"]),
                  sentiment_score:
                    get_in(transcript_data, [
                      "results",
                      "sentiments",
                      "average",
                      "sentiment_score"
                    ])
                }
              end)

            sentiment = %{
              type: "sentiment",
              vendor: "comcent",
              schema: "comcent.deepgram.nova2.v1",
              body:
                case Jason.encode(sentiments) do
                  {:ok, encoded} -> encoded
                  {:error, _} -> "{}"
                end,
              encoding: "json"
            }

            [sentiment, transcription]
          else
            [transcription]
          end
        rescue
          e ->
            Logger.error("Error processing transcripts: #{inspect(e)}")
            []
        end
      else
        try do
          summary =
            Repo.one(
              from a in CallAnalysis,
                where: a.call_story_id == ^call_story.id and a.type == "SUMMARY",
                select: %{
                  id: a.id,
                  provider: a.provider,
                  type: a.type,
                  analysis_data: a.analysis_data,
                  call_story_id: a.call_story_id
                }
            )

          if summary do
            summary_text = get_in(summary.analysis_data, ["results", "summary", "text"])

            summary_analysis = %{
              type: "summary",
              vendor: "comcent",
              schema: "comcent.deepgram.nova2.v1",
              body: summary_text,
              encoding: "text"
            }

            [summary_analysis | analysis]
          else
            analysis
          end
        rescue
          e ->
            Logger.error("Error processing summary: #{inspect(e)}")
            analysis
        end
      end
    rescue
      e ->
        Logger.error("Error in get_analysis: #{inspect(e)}")
        []
    end
  end
end
