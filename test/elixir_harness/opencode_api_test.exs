defmodule ElixirHarness.OpencodeApiTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.CLI.OpenCodeAPI

  defmodule ScriptedStub do
    @moduledoc false

    def start(script) do
      {:ok, agent} = Agent.start_link(fn -> script end)
      {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)
      pid = spawn(fn -> accept(listen, agent) end)
      on_exit_ref = {pid, listen}

      %{
        server: %{port: nil, base_url: "http://127.0.0.1:#{port}", auth: {"opencode", "s"}},
        cleanup: on_exit_ref
      }
    end

    defp accept(listen, agent) do
      case :gen_tcp.accept(listen, 5_000) do
        {:ok, sock} ->
          spawn(fn -> accept(listen, agent) end)
          serve(sock, agent)

        _ ->
          :ok
      end
    end

    defp serve(sock, agent) do
      with {:ok, data} <- :gen_tcp.recv(sock, 0, 5_000),
           [head | _] <- String.split(data, "\r\n"),
           [method, path | _] <- String.split(head, " ") do
        {status, body} =
          Agent.get_and_update(agent, fn
            [{^method, ^path, resp} | rest] -> {{200, resp}, rest}
            other -> {{200, ~s({"id":"ses_test","data":[]})}, other}
          end)

        :gen_tcp.send(
          sock,
          "HTTP/1.1 #{status} OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
        )
      end

      :gen_tcp.close(sock)
    end
  end

  @assistant ~s({"data":[{"type":"assistant","time":{"created":1,"completed":2},"content":[{"type":"text","text":"done it"}]}]})

  test "full turn: create, prompt, collect, diff" do
    %{server: server} =
      ScriptedStub.start([
        {"POST", "/api/session", ~s({"id":"ses_test"})},
        {"POST", "/api/session/ses_test/prompt", ~s({"data":{}})},
        {"GET", "/api/session/ses_test/message", ~s({"data":[]})},
        {"GET", "/api/session/ses_test/message", @assistant},
        {"GET", "/api/session/ses_test/message", @assistant},
        {"GET", "/api/session/ses_test/diff", ~s({"files":["a.ex"]})}
      ])

    assert {:ok, "done it"} =
             OpenCodeAPI.run("do the thing", server: server, poll_interval_ms: 10)

    assert {:ok, %{"files" => ["a.ex"]}} = OpenCodeAPI.diff(server, "ses_test")
  end

  test "timeout interrupts and errors" do
    %{server: server} =
      ScriptedStub.start([
        {"POST", "/api/session", ~s({"id":"ses_slow"})},
        {"POST", "/api/session/ses_slow/prompt", ~s({"data":{}})}
      ])

    assert {:error, :budget_time_exceeded} =
             OpenCodeAPI.run("take forever", server: server, max_ms: 100, poll_interval_ms: 10)
  end
end
