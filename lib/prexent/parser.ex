defmodule Prexent.Parser do
  @moduledoc """
  This module is the parser from markdown to HTML
  """
  require Logger

  @typedoc """
  A single slide
  """
  @type slide() :: [
          Map.t(
            type ::
              :html
              | :code
              | :header
              | :footer
              | :comment
              | :custom_css
              | :slide_background
              | :slide_classes
              | :global_background
              | :error,
            content :: String.t()
          )
        ]

  @typedoc """
  The result of the parse.
  This type will return a list of slides()
  """
  @type parse_result() :: [slide()]

  @doc """
  Parses slides of the markdown to a list of HTML.
  If exists any parse error, the item in the list will be the error message.

  It recognizes some commands:

  * `!include <file>` - with a markdown file to include in any place
  * `!code <file>` - will parse a code script
  """
  @spec to_parsed_list(String.t()) :: parse_result()
  def to_parsed_list(path_to_file) do
    try do
      read_file!(path_to_file)
      |> parse_content()
    rescue
      e in File.Error -> [e.message()]
    end
  end

  defp parse_content(content) do
    regex = ~r/(^---$)|(^!([\S*]+) ([\S*]+).*$)/m

    Regex.split(regex, content, include_captures: true, trim: true)
    |> Enum.map(&process_chunk(&1))
    |> List.flatten()
    |> split_on("---")
  end

  defp split_on(list, on) do
    list
    |> Enum.reverse()
    |> do_split_on(on, [[]])
    |> Enum.reject(fn list -> list == [] end)
  end

  defp do_split_on([], _, acc), do: acc
  defp do_split_on([h | t], h, acc), do: do_split_on(t, h, [[] | acc])
  defp do_split_on([h | t], on, [h2 | t2]), do: do_split_on(t, on, [[h | h2] | t2])

  defp process_chunk("---"), do: "---"

  defp process_chunk("!code " <> arguments), do: process_code(String.split(arguments, " "))

  defp process_code([fname]), do: process_code([fname, "elixir", "elixir"])

  defp process_code([fname, lang, runner]) do
    path_to_file = path_to_file(fname)

    try do
      file_content = read_file!(path_to_file)

      %{
        type: :code,
        content: file_content,
        filename: path_to_file,
        runner: runner,
        lang: lang
      }
    rescue
      _ ->
        process_error("Code file not found: #{path_to_file}")
    end
  end

  defp process_code(parameters) do
    process_error("invalid code parameters #{Enum.join(parameters, ' ')}")
  end

  defp process_chunk("!include " <> argument) do
    path_to_file = path_to_file(argument)

    try do
      read_file!(path_to_file)
      |> parse_content()
    rescue
      _ ->
        process_error("Included file not found: #{path_to_file}")
    end
  end

  defp process_chunk("!" <> rest) do
    case String.split(rest, " ") do
      ["header" | args] -> %{type: :header, content: Enum.join(args, " ")}
      ["footer" | args] -> %{type: :footer, content: Enum.join(args, " ")}
      ["comment" | args] -> %{type: :comment, content: Enum.join(args, " ")}
      ["custom_css" | args] -> %{type: :custom_css, content: Enum.at(args, 0)}
      ["global_background" | args] -> %{type: :global_background, content: Enum.at(args, 0)}
      ["slide_background" | args] -> %{type: :slide_background, content: Enum.at(args, 0)}
      ["slide_classes" | args] -> %{type: :slide_classes, content: args}
      _ -> %{type: :error, content: "wrong command !#{rest}"}
    end
  end

  defp process_chunk(chunk) do
    case Earmark.as_html(chunk) do
      {:ok, html_doc, _} ->
        %{
          type: :html,
          content: html_doc
        }

      {:error, _html_doc, error_messages} ->
        process_error(error_messages)
    end
  end

  defp process_error(content),
    do: %{
      type: :error,
      content: content
    }

  defp path_to_file(input) do
    input
    |> String.trim()
    |> String.split(" ")
    |> Enum.at(0)
  end

  defp read_file!(path_to_file) do
    abspath = Path.absname(path_to_file)
    File.read!(abspath)
  end
end
