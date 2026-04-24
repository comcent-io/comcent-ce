defmodule Comcent.Types.AuditLogType do
  @moduledoc """
  Defines the types of audit logs in the system.
  """

  @type t ::
          :CALL_TALK_TIME
          | :CALL_TRANSCRIPTION
          | :CALL_SENTIMENT_ANALYSIS
          | :CALL_SUMMARY_ANALYSIS
          | :CALL_RECORDING_S3_FILE_SIZE
          | :VOICEBOT

  @values [
    :CALL_TALK_TIME,
    :CALL_TRANSCRIPTION,
    :CALL_SENTIMENT_ANALYSIS,
    :CALL_SUMMARY_ANALYSIS,
    :CALL_RECORDING_S3_FILE_SIZE,
    :VOICEBOT
  ]

  def values, do: @values
end
