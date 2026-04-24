defmodule Comcent.Types.DeepgramResult do
  @moduledoc """
  Represents the structure of a Deepgram transcription result.
  """

  defstruct [
    :results
  ]

  @type t :: %__MODULE__{
          results: %{
            channels: [
              %{
                alternatives: [
                  %{
                    paragraphs: %{
                      paragraphs: [
                        %{
                          sentences: [
                            %{
                              text: String.t(),
                              start: number()
                            }
                          ]
                        }
                      ]
                    }
                  }
                ]
              }
            ]
          }
        }
end
