defmodule ElixirHarness.OpencodePolicyTest do
  use ExUnit.Case, async: true

  alias ElixirHarness.CLI.{OpenCodePolicy, OpenCodeEvents}

  test "decide allows listed actions, rejects everything else" do
    policy = %{rules: [{"write", ~r/^\/tmp\//, "once"}]}

    assert "once" =
             OpenCodePolicy.decide(%{"action" => "write", "resources" => ["/tmp/a.ex"]}, policy)

    assert "reject" =
             OpenCodePolicy.decide(%{"action" => "write", "resources" => ["/etc/passwd"]}, policy)

    assert "reject" =
             OpenCodePolicy.decide(%{"action" => "shell", "resources" => ["/tmp/a.ex"]}, policy)
  end

  test "poll loop replies to pending requests" do
    {:ok, agent} = Agent.start_link(fn -> :pending end)
    {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    parent = self()

    spawn(fn ->
      {:ok, sock} = :gen_tcp.accept(listen, 10_000)
      {:ok, _} = :gen_tcp.recv(sock, 0, 5_000)
      :gen_tcp.send(sock, reply(~s([{"id":"per1","action":"write","resources":["/tmp/a.ex"]}])))
      :gen_tcp.close(sock)

      {:ok, sock2} = :gen_tcp.accept(listen, 10_000)
      {:ok, data} = :gen_tcp.recv(sock2, 0, 5_000)

      if String.contains?(data, "POST") do
        send(parent, :replied)
        Agent.update(agent, fn _ -> :done end)
      end

      :gen_tcp.send(sock2, reply(~s([])))
      :gen_tcp.close(sock2)
    end)

    server = %{port: nil, base_url: "http://127.0.0.1:#{port}", auth: {"u", "p"}}

    {:ok, pid} =
      OpenCodePolicy.start_link(server, "ses_1", %{rules: [{"write", ~r/^\/tmp\//, "once"}]})

    assert_receive :replied, 3_000
    GenServer.stop(pid)
    :gen_tcp.close(listen)
  end

  test "events forward to PubSub" do
    {:ok, _} =
      Supervisor.start_link([{Phoenix.PubSub, name: ElixirHarness.PubSub}],
        strategy: :one_for_one
      )

    Phoenix.PubSub.subscribe(ElixirHarness.PubSub, OpenCodeEvents.topic())

    {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    spawn(fn ->
      {:ok, sock} = :gen_tcp.accept(listen, 10_000)
      {:ok, _} = :gen_tcp.recv(sock, 0, 5_000)
      body = "event: update\ndata: {\"text\":\"hi\"}\n\n"

      :gen_tcp.send(
        sock,
        "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
      )

      :gen_tcp.close(sock)
    end)

    server = %{port: nil, base_url: "http://127.0.0.1:#{port}", auth: {"u", "p"}}
    {:ok, pid} = OpenCodeEvents.start_link(server)
    assert_receive {:opencode_event, %{"text" => "hi"}}, 5_000
    GenServer.stop(pid)
    :gen_tcp.close(listen)
  end

  defp reply(body) do
    "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"
  end
end
