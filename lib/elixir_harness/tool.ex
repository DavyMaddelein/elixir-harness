defmodule ElixirHarness.Tool do
  @moduledoc """
  Behaviour for harness tools.

  Showcase of Elixir metaprogramming: `use ElixirHarness.Tool` plus
  `tool_name/1`, `tool_description/1`, `tool_schema/1` macros declare
  the contract; `validate/2` is pattern-matched type checking with no deps.
  """

  @callback tool_name() :: String.t()
  @callback tool_description() :: String.t()
  @callback tool_schema() :: %{String.t() => keyword()}
  @callback run(map()) :: {:ok, term()} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour ElixirHarness.Tool
      import ElixirHarness.Tool, only: [tool_name: 1, tool_description: 1, tool_schema: 1]
      Module.register_attribute(__MODULE__, :tool_name, persist: false)
      Module.register_attribute(__MODULE__, :tool_description, persist: false)
      Module.register_attribute(__MODULE__, :tool_schema, persist: false)
      @before_compile ElixirHarness.Tool
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @impl true
      def tool_name, do: @tool_name
      @impl true
      def tool_description, do: @tool_description
      @impl true
      def tool_schema, do: @tool_schema
    end
  end

  defmacro tool_name(name) do
    quote do
      @tool_name unquote(name)
    end
  end

  defmacro tool_description(desc) do
    quote do
      @tool_description unquote(desc)
    end
  end

  defmacro tool_schema(schema) do
    quote do
      @tool_schema unquote(schema)
    end
  end

  @doc "Validate args against a tool's schema. Returns `:ok` or `{:error, reason}`."
  @spec validate(module(), map()) :: :ok | {:error, String.t()}
  def validate(tool, args) when is_atom(tool) and is_map(args) do
    Enum.reduce_while(tool.tool_schema(), :ok, fn {field, opts}, :ok ->
      required = Keyword.get(opts, :required, false)
      type = Keyword.get(opts, :type, :any)

      case Map.fetch(args, field) do
        :error when required ->
          {:halt, {:error, "missing required arg: #{field}"}}

        :error ->
          {:cont, :ok}

        {:ok, v} ->
          if matches_type?(v, type),
            do: {:cont, :ok},
            else: {:halt, {:error, "bad type for #{field}: expected #{type}"}}
      end
    end)
  end

  @doc "Validate then run a tool."
  @spec call(module(), map()) :: {:ok, term()} | {:error, term()}
  def call(tool, args) do
    with :ok <- validate(tool, args), do: tool.run(args)
  end

  defp matches_type?(_v, :any), do: true
  defp matches_type?(v, :string), do: is_binary(v)
  defp matches_type?(v, :integer), do: is_integer(v)
  defp matches_type?(v, :float), do: is_float(v) or is_integer(v)
  defp matches_type?(v, :boolean), do: is_boolean(v)
  defp matches_type?(v, :list), do: is_list(v)
  defp matches_type?(v, :map), do: is_map(v)
  defp matches_type?(_v, _t), do: false
end
