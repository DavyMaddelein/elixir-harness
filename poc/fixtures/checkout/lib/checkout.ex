defmodule Checkout do
  @moduledoc "Tiny checkout service. Rate limiting lives in Checkout.RateLimiter (written by the train)."

  def charge(amount_cents, user_id) when is_integer(amount_cents) and amount_cents > 0 do
    :ok = Checkout.Audit.record(user_id, amount_cents)

    case Checkout.RateLimiter.check(user_id) do
      :allow -> {:ok, "charged #{amount_cents} for #{user_id}"}
      :deny -> {:error, :rate_limited}
    end
  end
end
