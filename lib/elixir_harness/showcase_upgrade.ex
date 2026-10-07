defmodule ElixirHarness.Showcase.Upgrade do
  @moduledoc """
  Showcase: hot code upgrade. A tool module is recompiled and reloaded
  into the running VM (`:code.purge` + `:code.load_binary` — the same
  per-module mechanism releases use) while its session never drops.
  """
  @behaviour ElixirHarness.Showcase

  @impl true
  def name, do: "upgrade"

  @impl true
  def description, do: "Hot code upgrade: redeploy a tool module mid-session, history intact."

  @impl true
  def run do
    mod = ElixirHarness.UpgradeDemo.Greeter
    {:ok, session} = ElixirHarness.Session.start_link()
    :ok = ElixirHarness.Session.append(session, "user", "greet me")

    IO.puts("1. Deploy greeter v1 into the running VM.")
    :ok = deploy(mod, 1)
    IO.puts("   #{apply(mod, :greet, ["agent"])} (session #{inspect(session)})")

    IO.puts("2. Hot-upgrade to v2: purge + load_binary, no restart.")
    :ok = deploy(mod, 2)
    IO.puts("   #{apply(mod, :greet, ["agent"])} (session #{inspect(session)})")

    IO.puts("3. Session survived with history:")
    IO.inspect(ElixirHarness.Session.history(session) |> Enum.map(& &1.role), label: "   roles")
    :ok
  end

  @doc "Compile version `vsn` of `mod` to a beam file, then purge + load it."
  @spec deploy(module(), 1 | 2) :: :ok
  def deploy(mod, vsn) do
    tag = System.unique_integer([:positive])
    dir = Path.join(System.tmp_dir!(), "harness_upgrade_#{vsn}_#{tag}")
    File.mkdir_p!(dir)
    src = Path.join(dir, "#{vsn}.ex")
    File.write!(src, source(mod, vsn))

    {:ok, [^mod], _} =
      Kernel.ParallelCompiler.compile_to_path([src], dir, return_diagnostics: true)

    beam =
      Path.join(dir, "Elixir." <> String.trim_leading(Atom.to_string(mod), "Elixir.") <> ".beam")

    _ = :code.purge(mod)
    {:module, ^mod} = :code.load_binary(mod, String.to_charlist(beam), File.read!(beam))
    :ok
  end

  defp source(mod, 1) do
    """
    defmodule #{inspect(mod)} do
      def version, do: 1
      def greet(name), do: "hello v1, \#{name}"
    end
    """
  end

  defp source(mod, 2) do
    """
    defmodule #{inspect(mod)} do
      def version, do: 2
      def greet(name), do: "hola v2, \#{name} — upgraded live"
    end
    """
  end
end
