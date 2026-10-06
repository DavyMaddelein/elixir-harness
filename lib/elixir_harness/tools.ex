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
