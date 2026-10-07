defmodule CheckoutAuditTest do
  use ExUnit.Case

  test "last charge is recorded" do
    assert {:ok, _} = Checkout.charge(100, "carol")
    assert 100 = Checkout.Audit.last("carol")
  end
end
