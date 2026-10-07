defmodule ElixirHarness.Tools.Math do
  @moduledoc "Sample tool: arithmetic."
  use ElixirHarness.Tool

  tool_name("math")
  tool_description("Add, subtract, or multiply two numbers.")

  tool_schema(%{
    "op" => [type: :string, required: true],
    "a" => [type: :float, required: true],
    "b" => [type: :float, required: true]
  })

  @impl true
  def run(%{"op" => "add", "a" => a, "b" => b}), do: {:ok, a + b}
  def run(%{"op" => "sub", "a" => a, "b" => b}), do: {:ok, a - b}
  def run(%{"op" => "mul", "a" => a, "b" => b}), do: {:ok, a * b}
  def run(%{"op" => op}), do: {:error, "unknown op: #{op}"}
end

defmodule ElixirHarness.Tools.Echo do
  @moduledoc "Sample tool: echo text back."
  use ElixirHarness.Tool

  tool_name("echo")
  tool_description("Echo text back to the caller.")
  tool_schema(%{"text" => [type: :string, required: true]})

  @impl true
  def run(%{"text" => t}), do: {:ok, t}
end

defmodule ElixirHarness.Tools.FileRead do
  @moduledoc "Sample tool: read a file relative to cwd."
  use ElixirHarness.Tool

  tool_name("file_read")
  tool_description("Read a file's contents.")
  tool_schema(%{"path" => [type: :string, required: true]})

  @impl true
  def run(%{"path" => path}) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, "read failed: #{:file.format_error(reason)}"}
    end
  end
end

defmodule ElixirHarness.Tools.Calc do
  @moduledoc """
  Safe formula evaluator: parses with `Code.string_to_quoted/1`, accepts
  only numeric literals and `+ - * /` (binary and unary minus), evaluates
  with empty bindings. Anything else — calls, variables, pipes, blocks —
  is rejected before evaluation.
  """
  use ElixirHarness.Tool

  tool_name("calc")
  tool_description("Evaluate an arithmetic expression, e.g. (1 + 2) * 3.")
  tool_schema(%{"expr" => [type: :string, required: true]})

  @impl true
  def run(%{"expr" => expr}) do
    with {:ok, ast} <- Code.string_to_quoted(expr),
         true <- safe?(ast) do
      try do
        {result, _} = Code.eval_quoted(ast, [])
        {:ok, result}
      rescue
        e in ArithmeticError -> {:error, "arithmetic error: #{Exception.message(e)}"}
      end
    else
      {:error, _} -> {:error, "could not parse expression"}
      false -> {:error, "unsafe expression: only numbers and + - * / allowed"}
    end
  end

  defp safe?({op, _, [l, r]}) when op in [:+, :-, :*, :/], do: safe?(l) and safe?(r)
  defp safe?({:-, _, [x]}), do: safe?(x)
  defp safe?(n) when is_number(n), do: true
  defp safe?(_), do: false
end
