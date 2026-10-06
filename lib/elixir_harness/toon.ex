defmodule ElixirHarness.Toon do
  @moduledoc """
  Thin wrapper over `toon_ex` (~1.7, spec v4.1).

  TOON is used as a translation layer: keep JSON-shaped maps in code,
  encode to TOON for LLM prompts / wire messages, decode back on receipt.

  Best for uniform object arrays (30-60% token saving). Deeply
  nested / non-uniform payloads may be smaller as JSON — callers decide.
  """

  @type encode_opt :: {:delimiter, String.t()} | {:indent, pos_integer()}
  @type decode_opt :: {:keys, :strings | :atoms} | {:strict, boolean()}

  @spec encode(term(), [encode_opt()]) :: {:ok, String.t()} | {:error, Exception.t()}
  def encode(data, opts \\ []) do
    :telemetry.span([:elixir_harness, :toon, :encode], %{system_time: System.system_time()}, fn ->
      result = ToonEx.encode(data, opts)
      {result, %{}}
    end)
  end

  @spec encode!(term(), [encode_opt()]) :: String.t()
  def encode!(data, opts \\ []) do
    :telemetry.span([:elixir_harness, :toon, :encode], %{system_time: System.system_time()}, fn ->
      {ToonEx.encode!(data, opts), %{}}
    end)
  end

  @spec decode(String.t(), [decode_opt()]) :: {:ok, term()} | {:error, Exception.t()}
  def decode(input, opts \\ []) do
    :telemetry.span([:elixir_harness, :toon, :decode], %{system_time: System.system_time()}, fn ->
      result = ToonEx.decode(input, opts)
      {result, %{}}
    end)
  end

  @spec decode!(String.t(), [decode_opt()]) :: term()
  def decode!(input, opts \\ []) do
    :telemetry.span([:elixir_harness, :toon, :decode], %{system_time: System.system_time()}, fn ->
      {ToonEx.decode!(input, opts), %{}}
    end)
  end

  @doc """
  Stream-encode an enumerable of uniform maps in chunks.

  Each chunk becomes one self-contained TOON document under `key`,
  so a large memory dump never builds one giant binary. Returns a
  `Stream` of binaries.
  """
  @spec encode_stream(Enumerable.t(), String.t(), keyword()) :: Enumerable.t()
  def encode_stream(rows, key, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 100)
    encode_opts = Keyword.drop(opts, [:chunk_size])

    rows
    |> Stream.chunk_every(chunk_size)
    |> Stream.map(&encode!(%{key => &1}, encode_opts))
  end

  @doc """
  Rough size comparison for notebooks: JSON bytes vs TOON bytes.
  Token estimate uses ~4 bytes/token heuristic.
  """
  @spec stats(term()) :: %{
          json_bytes: non_neg_integer(),
          toon_bytes: non_neg_integer(),
          saved_pct: float()
        }
  def stats(data) do
    json = :json.encode(data) |> IO.iodata_to_binary()
    toon = encode!(data)
    jb = byte_size(json)
    tb = byte_size(toon)

    %{json_bytes: jb, toon_bytes: tb, saved_pct: Float.round((jb - tb) / max(jb, 1) * 100, 1)}
  end
end
