defmodule ElixirHarness.Plan do
  @moduledoc """
  Compile-time plans: `defplan` with `step`s expands to a supervised
  task graph. Dependencies are validated at compile time — unknown deps
  and cycles fail the build, not the demo.

      defplan "research" do
        step :fetch, tool: MyTool, args: %{}
        step :report, tool: MyTool, args: %{}, depends_on: [:fetch]
      end
  """

  defmacro __using__(_opts) do
    quote do
      import ElixirHarness.Plan, only: [defplan: 2, step: 2]
      Module.register_attribute(__MODULE__, :plans, accumulate: true)
      @before_compile ElixirHarness.Plan
    end
  end

  defmacro defplan(name, do: block) do
    quote do
      Module.register_attribute(__MODULE__, :steps, accumulate: true)
      unquote(block)
      @plans {unquote(name), Enum.reverse(@steps)}
      Module.delete_attribute(__MODULE__, :steps)
    end
  end

  defmacro step(id, opts) do
    quote do
      @steps %{
        id: unquote(id),
        tool: Keyword.fetch!(unquote(opts), :tool),
        args: Keyword.get(unquote(opts), :args, %{}),
        depends_on: Keyword.get(unquote(opts), :depends_on, [])
      }
    end
  end

  defmacro __before_compile__(env) do
    plans = Module.get_attribute(env.module, :plans)

    for {name, steps} <- plans do
      validate!(name, steps)
    end

    quote do
      def __plans__, do: unquote(Macro.escape(plans))
    end
  end

  @doc false
  def validate!(name, steps) do
    ids = MapSet.new(steps, & &1.id)

    if length(steps) != MapSet.size(ids) do
      raise ArgumentError, "plan #{inspect(name)} has duplicate step ids"
    end

    for %{id: id, depends_on: deps} <- steps, dep <- deps do
      unless MapSet.member?(ids, dep) do
        raise ArgumentError,
              "plan #{inspect(name)} step #{inspect(id)} depends on unknown step #{inspect(dep)}"
      end
    end

    if has_cycle?(steps) do
      raise ArgumentError, "plan #{inspect(name)} has a dependency cycle"
    end

    :ok
  end

  defp has_cycle?(steps) do
    deps = Map.new(steps, &{&1.id, &1.depends_on})
    Enum.any?(Map.keys(deps), &cyclic?(&1, deps, MapSet.new()))
  end

  defp cyclic?(node, deps, seen) do
    cond do
      MapSet.member?(seen, node) -> true
      true -> Enum.any?(Map.get(deps, node, []), &cyclic?(&1, deps, MapSet.put(seen, node)))
    end
  end

  @doc "Run a plan: topological levels, each fanned out, failures halt dependents."
  @spec run([{String.t(), [map()]}], String.t(), keyword()) ::
          {:ok, %{atom() => {:ok, term()} | {:error, term()} | {:skipped, atom()}}}
          | {:error, :unknown_plan}
  def run(plans, name, opts \\ []) do
    case List.keyfind(plans, name, 0) do
      nil -> {:error, :unknown_plan}
      {_name, steps} -> run_steps(steps, opts)
    end
  end

  defp run_steps(steps, opts) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 4)

    steps
    |> levels()
    |> Enum.reduce(%{}, fn level, results ->
      level
      |> Task.async_stream(
        fn step ->
          case failed_dep(step, results) do
            nil -> {step.id, ElixirHarness.ToolRunner.run(step.tool, step.args, timeout: timeout)}
            dep -> {step.id, {:skipped, dep}}
          end
        end,
        max_concurrency: max_concurrency,
        ordered: false,
        timeout: timeout + 5_000
      )
      |> Enum.reduce(results, fn
        {:ok, {id, result}}, acc -> Map.put(acc, id, result)
        {:exit, _}, acc -> acc
      end)
    end)
    |> then(&{:ok, &1})
  end

  defp failed_dep(%{depends_on: deps}, results) do
    Enum.find(deps, &(!match?({:ok, _}, Map.get(results, &1))))
  end

  defp levels(steps) do
    deps = Map.new(steps, &{&1.id, &1.depends_on})

    Stream.unfold({steps, MapSet.new()}, fn
      {[], _} ->
        nil

      {rest, done} ->
        {ready, pending} =
          Enum.split_with(rest, &Enum.all?(&1.depends_on, fn d -> MapSet.member?(done, d) end))

        if ready == [],
          do: nil,
          else: {ready, {pending, Enum.reduce(ready, done, &MapSet.put(&2, &1.id))}}
    end)
    |> Enum.to_list()
  end
end

defmodule ElixirHarness.Showcase.Plan do
  @moduledoc "Showcase: a diamond plan with one failure halting its dependents."
  @behaviour ElixirHarness.Showcase

  use ElixirHarness.Plan

  alias ElixirHarness.Tools.{Math, Echo}

  defmodule Boom do
    use ElixirHarness.Tool
    tool_name("boom")
    tool_description("Raises.")
    tool_schema(%{})
    @impl true
    def run(_), do: raise("plan boom")
  end

  defplan "demo" do
    step(:a, tool: Math, args: %{"op" => "add", "a" => 1, "b" => 1})
    step(:b, tool: Echo, args: %{"text" => "hi"})
    step(:boom, tool: Boom, args: %{}, depends_on: [:a])
    step(:after_boom, tool: Echo, args: %{"text" => "never"}, depends_on: [:boom])
    step(:join, tool: Echo, args: %{"text" => "joined"}, depends_on: [:a, :b])
  end

  @impl true
  def name, do: "plan"

  @impl true
  def description, do: "defplan DSL: diamond graph, one failure halts only its dependents."

  @impl true
  def run do
    {:ok, results} = ElixirHarness.Plan.run(__plans__(), "demo")

    for id <- [:a, :b, :boom, :after_boom, :join] do
      IO.inspect(Map.fetch!(results, id), label: "  #{id}")
    end

    :ok
  end
end
