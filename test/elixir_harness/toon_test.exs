defmodule ElixirHarness.ToonTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.Toon

  test "round-trips uniform payload" do
    data = %{"users" => [%{"id" => 1, "name" => "Ada"}, %{"id" => 2, "name" => "Bob"}]}
    assert {:ok, text} = Toon.encode(data)
    assert text =~ "users[2]{id,name}:"
    assert {:ok, ^data} = Toon.decode(text)
  end

  test "round-trips nested payload" do
    data = %{"user" => %{"name" => "Bob", "tags" => ["elixir", "toon"]}}
    assert Toon.decode!(Toon.encode!(data)) == data
  end

  test "truncated tabular input returns error (strict guardrail)" do
    assert {:error, _} = Toon.decode("users[2]{id,name}:\n  1,Ada\n")
  end

  test "stream encode decodes back to full rows" do
    rows = for i <- 1..250, do: %{"id" => i, "name" => "n#{i}"}

    chunks =
      Toon.encode_stream(rows, "users", chunk_size: 100)
      |> Enum.to_list()

    assert length(chunks) == 3

    decoded =
      Enum.flat_map(chunks, fn c ->
        assert {:ok, %{"users" => batch}} = Toon.decode(c)
        batch
      end)

    assert length(decoded) == 250
    assert hd(decoded)["id"] == 1
  end

  test "stats reports savings on uniform data" do
    data = %{"users" => for(i <- 1..10, do: %{"id" => i, "name" => "n#{i}", "role" => "user"})}
    %{json_bytes: jb, toon_bytes: tb, saved_pct: pct} = Toon.stats(data)
    assert tb < jb
    assert pct > 0
  end
end
