defmodule ComcentWeb.Layouts do
  @moduledoc """
  This module contains different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton to wrap all your live views and
  regular views. It can be customized with different layouts.
  """
  use ComcentWeb, :html

  embed_templates "layouts/*"
end
