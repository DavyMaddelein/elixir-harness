defmodule ElixirHarness.CLI.OpenCode.Server do
  @moduledoc """
  Lifecycle for `opencode serve`: boot it as an OS process, wait for
  `/api/info` to answer, stop it cleanly. A crashed server is just a
  dead port — supervise or restart it like anything else.
  """

  alias ElixirHarness.CLI.OpenCode.Http

  @doc "Boot a server. Returns `{:ok, %{port, base_url, auth}}`."
  @spec boot(keyword()) :: {:ok, map()} | {:error, term()}
  def boot(opts \\ []) do
    exe = Keyword.get(opts, :exe, "opencode")
    port = Keyword.get(opts, :port, 4096)

    password =
      Keyword.get_lazy(opts, :password, fn ->
        System.get_env("OPENCODE_SERVER_PASSWORD") || default_password()
      end)

    timeout = Keyword.get(opts, :timeout, 30_000)

    exe_path = System.find_executable(exe) || exe
    env = [{~c"OPENCODE_SERVER_PASSWORD", String.to_charlist(password)}]

    os_port =
      Port.open({:spawn_executable, exe_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["serve", "--port", to_string(port)],
        env: env
      ])

    server = %{port: os_port, base_url: "http://127.0.0.1:#{port}", auth: {"opencode", password}}

    case wait_healthy(server, timeout) do
      :ok ->
        {:ok, server}

      {:error, _} = err ->
        stop(server)
        err
    end
  end

  @doc "Stop a server."
  @spec stop(map()) :: :ok
  def stop(%{port: port}) do
    if Port.info(port) != :undefined do
      try do
        Port.close(port)
      catch
        _, _ -> :ok
      end
    end

    :ok
  end

  defp wait_healthy(server, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(server, deadline)
  end

  defp poll(server, deadline) do
    case Http.get(server, "/api/info") do
      {:ok, _} ->
        :ok

      _ ->
        cond do
          System.monotonic_time(:millisecond) > deadline ->
            {:error, :server_boot_timeout}

          Port.info(server.port) == :undefined ->
            {:error, :server_died}

          true ->
            Process.sleep(200)
            poll(server, deadline)
        end
    end
  end

  defp default_password, do: Base.encode64(:crypto.strong_rand_bytes(24))
end

defmodule ElixirHarness.CLI.OpenCode.Http do
  @moduledoc """
  Zero-dep HTTP client for the opencode server: `:httpc` transport,
  OTP `:json` codec, basic auth. Returns `{:ok, decoded}` for 2xx,
  `{:error, {status, body}}` otherwise.
  """

  @doc "GET `path` (e.g. `/api/info`)."
  @spec get(map(), String.t()) :: {:ok, term()} | {:error, term()}
  def get(server, path) do
    request(server, :get, path, nil)
  end

  @doc "POST `path` with a JSON-encodable `body`."
  @spec post(map(), String.t(), term()) :: {:ok, term()} | {:error, term()}
  def post(server, path, body) do
    request(server, :post, path, body)
  end

  @doc "DELETE `path`."
  @spec delete(map(), String.t()) :: {:ok, term()} | {:error, term()}
  def delete(server, path) do
    request(server, :delete, path, nil)
  end

  @doc """
  Stream `path` as SSE, invoking `on_event.(event_map)` per decoded
  event. Returns `:ok` when the stream ends or `max_ms` elapses.
  """
  @spec sse(map(), String.t(), (map() -> any()), keyword()) :: :ok | {:error, term()}
  def sse(server, path, on_event, opts \\ []) do
    :ok = ensure_code_path()
    max_ms = Keyword.get(opts, :max_ms, 30_000)
    {user, pass} = server.auth
    url = String.to_charlist(server.base_url <> path)
    headers = auth_headers(user, pass) ++ [{~c"accept", ~c"text/event-stream"}]
    http_opts = [{:timeout, max_ms + 5_000}]

    case :httpc.request(:get, {url, headers}, http_opts, sync: false, stream: :self) do
      {:ok, ref} -> sse_loop(ref, "", on_event, System.monotonic_time(:millisecond) + max_ms)
      {:error, _} = err -> err
    end
  end

  defp sse_loop(ref, buf, on_event, deadline) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:http, {^ref, :stream_start, _}} ->
        sse_loop(ref, buf, on_event, deadline)

      {:http, {^ref, :stream, data}} ->
        sse_loop(
          ref,
          drain_events(buf <> IO.iodata_to_binary(data), on_event),
          on_event,
          deadline
        )

      {:http, {^ref, :stream_end, _}} ->
        :ok

      {:http, {^ref, {{_, status, _}, _, _}}} when status >= 400 ->
        {:error, {:http_status, status}}
    after
      timeout ->
        :httpc.cancel_request(ref)
        :ok
    end
  end

  defp drain_events(buf, on_event) do
    case :binary.split(buf, "\n\n") do
      [chunk, rest] ->
        if event = parse_event(chunk), do: on_event.(event)
        drain_events(rest, on_event)

      [_partial] ->
        buf
    end
  end

  defp parse_event(chunk) do
    data =
      chunk
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&(String.trim_leading(&1, "data:") |> String.trim()))
      |> Enum.join("\n")

    case data do
      "" -> nil
      "[DONE]" -> nil
      json -> decode_json(json)
    end
  end

  defp decode_json(json) do
    try do
      :json.decode(json)
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp request(server, method, path, body) do
    :ok = ensure_code_path()
    :ok = Application.ensure_started(:inets)
    {user, pass} = server.auth
    url = String.to_charlist(server.base_url <> path)
    headers = auth_headers(user, pass)
    http_opts = [{:timeout, 15_000}]

    req =
      case body do
        nil -> {url, headers}
        _ -> {url, headers, ~c"application/json", :json.encode(body)}
      end

    case :httpc.request(method, req, http_opts, []) do
      {:ok, {{_, status, _}, _, resp_body}} when status in 200..299 ->
        {:ok, decode_body(resp_body)}

      {:ok, {{_, status, _}, _, resp_body}} ->
        {:error, {status, IO.iodata_to_binary(resp_body)}}

      {:error, _} = err ->
        err
    end
  end

  defp decode_body([]), do: nil
  defp decode_body(""), do: nil

  defp decode_body(body) do
    binary = IO.iodata_to_binary(body)

    case String.trim(binary) do
      "" -> nil
      "{" <> _ = obj -> decode_json(obj) || binary
      "[" <> _ = arr -> decode_json(arr) || binary
      _ -> binary
    end
  end

  defp auth_headers(user, pass) do
    [{~c"authorization", String.to_charlist("Basic " <> Base.encode64("#{user}:#{pass}"))}]
  end

  # Mix prunes OTP lib dirs off the code path; make sure inets is
  # loadable wherever this client runs (releases include it via
  # extra_applications).
  defp ensure_code_path do
    unless Code.ensure_loaded?(:httpc) do
      :code.add_patha(:code.lib_dir(:inets) ++ ~c"/ebin")
    end

    :ok
  end
end
