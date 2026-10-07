defmodule ElixirHarness.DashboardTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ElixirHarness.Dashboard.{Introspect, TelemetryBridge}

  @endpoint ElixirHarnessWeb.Endpoint

  test "tree contains the tool supervisor" do
    ids = Introspect.tree() |> Enum.map(& &1.id)
    assert "ElixirHarness.ToolSupervisor" in ids
  end

  test "workers lists started agents with pg membership" do
    {:ok, _} = ElixirHarness.Orchestrator.start_worker("dash-w1")
    workers = Introspect.workers()
    assert Enum.any?(workers, &(&1.id == inspect("dash-w1") and &1.in_pg))
  end

  test "vm stats come from the runtime" do
    %{processes: p, schedulers: s, nodes: n} = Introspect.vm_stats()
    assert p > 0 and s > 0 and is_list(n)
  end

  setup do
    Application.put_env(:phoenix, :json_library, ElixirHarnessWeb.Json)

    Application.put_env(:elixir_harness, ElixirHarnessWeb.Endpoint,
      secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48)),
      live_view: [signing_salt: "test-salt"],
      pubsub_server: ElixirHarness.PubSub
    )

    start_supervised!({Phoenix.PubSub, name: ElixirHarness.PubSub})
    start_supervised!(ElixirHarnessWeb.Endpoint)
    TelemetryBridge.attach()
    :ok
  end

  test "mission control renders live and logs traffic" do
    {:ok, view, html} = live(build_conn(), "/")
    assert html =~ "Mission Control"
    assert html =~ "ElixirHarness.ToolSupervisor"

    render_click(view, "traffic")
    assert eventually(fn -> render(view) =~ "math" end)
  end

  test "showcases run from the page and stream output" do
    {:ok, view, _} = live(build_conn(), "/")
    assert render(view) =~ "calc"
    render_click(view, "run_showcase", %{"name" => "calc"})
    assert eventually(fn -> render(view) =~ "rejected before eval" end)
  end

  test "socket serializer round-trips a LiveView join frame on OTP :json" do
    alias Phoenix.Socket.{Message, V2}
    frame = ~s(["1","1","lv:test","phx_join",{"url":"http://localhost:4000/"}])

    assert %Message{topic: "lv:test", event: "phx_join", payload: %{"url" => _}} =
             V2.JSONSerializer.decode!(frame, opcode: :text)

    {:socket_push, :text, iodata} =
      V2.JSONSerializer.encode!(%Message{
        topic: "lv:test",
        event: "phx_reply",
        payload: %{"status" => "ok"}
      })

    assert IO.iodata_to_binary(iodata) =~ "phx_reply"
  end

  defp eventually(fun, tries \\ 50) do
    if fun.() do
      true
    else
      Process.sleep(100)
      if tries > 1, do: eventually(fun, tries - 1), else: flunk("condition not met")
    end
  end
end
