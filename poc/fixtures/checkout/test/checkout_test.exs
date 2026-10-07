defmodule CheckoutTest do
  use ExUnit.Case

  test "charges a normal payment" do
    assert {:ok, _} = Checkout.charge(100, "alice")
  end

  test "rate limits after 3 charges" do
    assert {:ok, _} = Checkout.charge(100, "bob")
    assert {:ok, _} = Checkout.charge(100, "bob")
    assert {:ok, _} = Checkout.charge(100, "bob")
    assert {:error, :rate_limited} = Checkout.charge(100, "bob")
  end
end
