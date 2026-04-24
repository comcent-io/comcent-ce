defmodule Comcent.Types.VCon do
  @moduledoc """
  Types for VCon (Voice Conversation) data structure.
  """

  @type vcon_version :: String.t()
  @type uuid :: String.t()
  @type date :: DateTime.t()
  @type duration :: non_neg_integer()
  @type party_index :: non_neg_integer()
  @type dialog_index :: non_neg_integer()

  @type civic_address :: %{
          optional(:country) => String.t(),
          optional(:a1) => String.t(),
          optional(:a2) => String.t(),
          optional(:a3) => String.t(),
          optional(:a4) => String.t(),
          optional(:a5) => String.t(),
          optional(:a6) => String.t(),
          optional(:prd) => String.t(),
          optional(:pod) => String.t(),
          optional(:sts) => String.t(),
          optional(:hno) => String.t(),
          optional(:hns) => String.t(),
          optional(:lmk) => String.t(),
          optional(:loc) => String.t(),
          optional(:flr) => String.t(),
          optional(:nam) => String.t(),
          optional(:pc) => String.t()
        }

  @type party :: %{
          optional(:tel) => String.t(),
          optional(:stir) => String.t(),
          optional(:mailto) => String.t(),
          optional(:name) => String.t(),
          optional(:validation) => String.t(),
          optional(:jCard) => any(),
          optional(:gmlpos) => String.t(),
          optional(:civicaddress) => civic_address(),
          optional(:timezone) => String.t()
        }

  @type dialog_type :: :recording | :text | :transfer | :incomplete

  @type mime_type ::
          :"text/plain"
          | :"audio/x-wav"
          | :"audio/x-mp3"
          | :"audio/x-mp4"
          | :"audio/ogg"
          | :"video/x-mp4"
          | :"video/ogg"
          | :"multipart/mixed"

  @type dialog_disposition ::
          :"no-answer"
          | :congestion
          | :failed
          | :busy
          | :"hung-up"
          | :"voicemail-no-message"

  @type dialog :: %{
          required(:type) => dialog_type(),
          optional(:start) => date(),
          optional(:duration) => duration(),
          optional(:parties) => party_index() | [party_index()],
          optional(:originator) => party_index(),
          optional(:mimetype) => mime_type(),
          optional(:filename) => String.t(),
          optional(:body) => String.t(),
          optional(:encoding) => String.t(),
          optional(:url) => String.t(),
          optional(:alg) => String.t(),
          optional(:signature) => String.t(),
          optional(:disposition) => dialog_disposition(),
          optional(:transferee) => party_index(),
          optional(:transferor) => party_index(),
          optional(:transferTarget) => party_index(),
          optional(:original) => dialog_index(),
          optional(:consultation) => dialog_index(),
          optional(:targetDialog) => dialog_index()
        }

  @type attachment :: %{
          required(:party) => party_index(),
          optional(:type) => String.t(),
          optional(:mimetype) => String.t(),
          optional(:filename) => String.t(),
          optional(:body) => String.t(),
          optional(:encoding) => String.t(),
          optional(:url) => String.t(),
          optional(:alg) => String.t(),
          optional(:signature) => String.t()
        }

  @type analysis :: %{
          required(:type) => String.t(),
          required(:vendor) => String.t(),
          optional(:dialog) => dialog_index() | [dialog_index()],
          optional(:mimeType) => String.t(),
          optional(:filename) => String.t(),
          optional(:product) => String.t(),
          optional(:schema) => String.t(),
          optional(:body) => String.t(),
          optional(:encoding) => String.t(),
          optional(:url) => String.t(),
          optional(:alg) => String.t(),
          optional(:signature) => String.t()
        }

  @type t :: %{
          required(:vcon) => vcon_version(),
          required(:uuid) => uuid(),
          required(:created_at) => date(),
          required(:parties) => [party()],
          required(:dialog) => [dialog()],
          required(:attachments) => [attachment()],
          required(:analysis) => [analysis()]
        }
end
