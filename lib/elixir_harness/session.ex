defmodule ElixirHarness.Session do
  @moduledoc """
  GenServer owning one session's memory table.

  The ETS table dies with this process — concurrent reads are safe,
  crashes are isolated per session by supervision.
  """
  use GenServer

  alias ElixirHarness.Memory.ETS
  alias ElixirHarness.Toon

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def append(session, role, content) do
    GenServer.call(session, {:append, role, content})
  end

  def history(session) do
    GenServer.call(session, :history)
  end

  def clear(session) do
    GenServer.call(session, :clear)
  end

  @doc "History encoded as TOON for prompt injection."
  def to_prompt(session) do
    session
    |> history()
    |> Enum.map(&%{"role" => &1.role, "content" => &1.content})
    |> then(&Toon.encode!(%{"history" => &1}))
  end

  @impl true
  def init(:ok) do
    {:ok, %{table: ETS.new()}, {:continue, :hibernate_ok}}
  end

  @impl true
  def handle_continue(:hibernate_ok, state), do: {:noreply, state, :hibernate}

  @impl true
  def handle_call({:append, role, content}, _from, %{table: t} = s) do
    :ok = ETS.append(t, %{role: role, content: content, at: System.system_time(:second)})
    {:reply, :ok, s}
  end

  def handle_call(:history, _from, %{table: t} = s), do: {:reply, ETS.list(t), s}

  def handle_call(:clear, _from, %{table: t} = s),
    do: {:reply, :ok, s} |> tap(fn _ -> ETS.clear(t) end)
end
