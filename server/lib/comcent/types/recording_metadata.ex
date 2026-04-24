defmodule Comcent.Types.RecordingMetadata do
  @moduledoc """
  Represents metadata for a recording.
  """

  @type direction :: :in | :both

  @type t :: %__MODULE__{
          file_name: String.t(),
          sha512: String.t(),
          direction: direction(),
          # in bytes
          file_size: String.t()
        }

  defstruct [:file_name, :sha512, :direction, :file_size]
end
