# CE-only stub. The real Comcent.Money lives in EE. CE doesn't meter or bill,
# so every conversion returns zero. Do NOT sync this file to EE.
defmodule Comcent.Money do
  @moduledoc false
  def convert_wallet_balance_to_dollars(_balance), do: 0.0
  def convert_dollars_to_wallet_balance(_dollars), do: 0
end
