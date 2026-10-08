defmodule ElixirHarness.OpencodeServerTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.CLI.OpenCode.{Server, Http}

  defmodule Stub do
    @moduledoc false

    def start(expect_user, expect_pass) do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)
      pid = spawn(fn -> accept(listen, expect_user, expect_pass) end)
      %{pid: pid, listen: listen, base_url: "http://127.0.0.1:#{port}"}
    end

    def stop(%{listen: listen}), do: :gen_tcp.close(listen)

    defp accept(listen, user, pass) do
      case :gen_tcp.accept(listen, 5_000) do
        {:ok, sock} ->
          spawn(fn -> accept(listen, user, pass) end)
          serve(sock, user, pass)

        {:error, :closed} ->
          :ok

        {:error, _} ->
          accept(listen, user, pass)
      end
    end

    defp serve(sock, user, pass) do
      case read_request(sock, "") do
        {:ok, method, path, headers, _body} ->
          if authorized?(headers, user, pass),
            do: respond(sock, method, path),
            else: send_resp(sock, 401, "nope")

        :error ->
          :ok
      end

      :gen_tcp.close(sock)
    end

    defp read_request(sock, acc) do
      case :gen_tcp.recv(sock, 0, 5_000) do
        {:ok, data} ->
          buf = acc <> data

          case :binary.split(buf, "\r\n\r\n") do
            [head, body] ->
              [request_line | header_lines] = String.split(head, "\r\n")
              [method, path | _] = String.split(request_line, " ")
              {:ok, method, path, header_lines, body}

            [_] ->
              read_request(sock, buf)
          end

        {:error, _} ->
          :error
      end
    end

    defp authorized?(headers, user, pass) do
      want = Base.encode64("#{user}:#{pass}")

      Enum.any?(headers, fn line ->
        case String.split(line, ":", parts: 2) do
          [name, value] ->
            String.trim(name) == "authorization" and
              match?(["basic", ^want], parse_basic(value))

          _ ->
            false
        end
      end)
    end

    defp parse_basic(value) do
      case Regex.run(~r/^basic\s+(.+)$/i, String.trim(value)) do
        [_, credentials] -> ["basic", credentials]
        _ -> []
      end
    end

    defp respond(sock, "GET", "/api/info"), do: send_resp(sock, 200, ~s({"healthy":true}))
    defp respond(sock, "POST", "/api/echo"), do: send_resp(sock, 200, ~s({"echo":true}))
    defp respond(sock, "GET", "/api/missing"), do: send_resp(sock, 404, "nah")

    defp respond(sock, "GET", "/api/event") do
      body = "event: message\ndata: {\"a\":1}\n\nevent: message\ndata: {\"b\":2}\n\n"
      send_resp(sock, 200, body, "text/event-stream")
    end

    defp respond(sock, _, _), do: send_resp(sock, 404, "nah")

    defp send_resp(sock, status, body, content_type \\ "application/json") do
      reason = %{200 => "OK", 401 => "Unauthorized", 404 => "Not Found"}[status]

      :gen_tcp.send(
        sock,
        "HTTP/1.1 #{status} #{reason}\r\ncontent-type: #{content_type}\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
      )
    end
  end

  setup do
    stub = Stub.start("opencode", "secret")
    on_exit(fn -> Stub.stop(stub) end)
    {:ok, server: %{port: nil, base_url: stub.base_url, auth: {"opencode", "secret"}}}
  end

  test "authed JSON round-trip", %{server: s} do
    assert {:ok, %{"healthy" => true}} = Http.get(s, "/api/info")
    assert {:ok, %{"echo" => true}} = Http.post(s, "/api/echo", %{"x" => 1})
  end

  test "auth failure and 404 surface as errors", %{server: s} do
    assert {:error, {401, _}} = Http.get(%{s | auth: {"opencode", "wrong"}}, "/api/info")
    assert {:error, {404, _}} = Http.get(s, "/api/missing")
  end

  test "SSE events parse", %{server: s} do
    parent = self()
    assert :ok = Http.sse(s, "/api/event", fn e -> send(parent, {:ev, e}) end, max_ms: 5_000)
    assert_receive {:ev, %{"a" => 1}}, 2_000
    assert_receive {:ev, %{"b" => 2}}, 2_000
  end

  test "real server boots, health-checks, and stops" do
    assert {:ok, server} =
             Server.boot(exe: "opencode", port: 4123, password: "test-secret", timeout: 30_000)

    assert {:ok, _} = Http.get(server, "/api/info")
    assert :ok = Server.stop(server)
  end
end
