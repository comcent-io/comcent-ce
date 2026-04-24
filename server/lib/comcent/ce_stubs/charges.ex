# CE-only stub. The real Comcent.Charges lives in EE. CE doesn't charge.
# Do NOT sync this file to EE.
defmodule Comcent.Charges do
  @moduledoc false
  def charge_for_call_minutes(_call_story), do: :ok
  def update_storage_used_for_call_recordings(_call_story), do: :ok
end
