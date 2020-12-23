defmodule SurfaceFormatter do
  @moduledoc """
  Houses code to format Surface code snippets. (In the form of strings.)
  """

  # Use 2 spaces for a tab
  @tab "  "

  # Line length of opening tags before splitting attributes onto their own line
  @max_line_length 80

  @typedoc "A node output by &Surface.Compiler.Parser.parse/1"
  @type parsed_surface_node :: term

  @typedoc "An HTML/Surface tag"
  @type tag :: String.t()

  @typedoc """
  An HTML/Surface attribute string, such as `class="container"`,
  `width=6`, or `items={{ @cart_items }}`
  """
  @type attribute :: String.t()

  @typedoc "Children of an HTML element"
  @type children :: list(code_segment)

  @typedoc "A segment of HTML that can be rendered given a tab level"
  @type code_segment :: String.t() | {tag, list(attribute), children}

  def format_string!(string) do
    string
    |> Surface.Compiler.Parser.parse()
    |> elem(1)
    |> Enum.map(&code_segment/1)
    |> Enum.map(&render/1)
    |> List.flatten()
    |> Enum.join("\n")
  end

  @spec code_segment(parsed_surface_node) :: code_segment
  defp code_segment({:interpolation, expression, _meta}) do
    "{{ #{Code.format_string!(expression)} }}"
  end

  defp code_segment(html) when is_binary(html) do
    case String.trim(html) do
      "" ->
        # This string only contained whitespace, so make sure we format
        # this as a newline as long as the string contains at least 2 newlines
        newlines =
          html
          |> String.graphemes()
          |> Enum.count(& &1 == "\n")

        if newlines > 1 do
          "\n"
        else
          ""
        end

      trimmed ->
        trimmed
    end
  end

  defp code_segment({"#" <> _macro_component = tag, attributes, [text_inside_macro_component], _meta}) do
    {
      tag,
      Enum.map(attributes, &render_attribute/1),
      [text_inside_macro_component]
    }
  end

  defp code_segment({tag, attributes, children, _meta}) do
    {
      tag,
      Enum.map(attributes, &render_attribute/1),
      Enum.map(children, &code_segment/1)
    }
  end

  defp render_attribute({name, value, _meta}) when is_binary(value),
    do: "#{name}=\"#{String.trim(value)}\""

  # For `true` boolean attributes, simply including the name of the attribute
  # without `=true` is shorthand for `=true`.
  defp render_attribute({name, true, _meta}),
    do: "#{name}"

  defp render_attribute({name, false, _meta}),
    do: "#{name}=false"

  defp render_attribute({name, value, _meta}) when is_number(value),
    do: "#{name}=#{value}"

  defp render_attribute({name, {:attribute_expr, expression, _expr_meta}, _meta}) when is_binary(expression) do
    formatted_expression =
      # Wrap it in square brackets (and then remove after formatting)
      # to support Surface sugar like this: `{{ foo: "bar" }}` (which is
      # equivalent to `{{ [foo: "bar"] }}`
      "[#{expression}]"
      |> Code.format_string!()
      |> Enum.slice(1..-2)
      |> to_string()

    if String.contains?(formatted_expression, "\n") do
      # Don't add extra space characters around the curly braces because
      # the formatted elixir code has newlines in it; this helps indentation
      # to line up.
      "#{name}={{#{formatted_expression}}}"
    else
      "#{name}={{ #{formatted_expression} }}"
    end
  end

  @spec render(code_segment) :: String.t() | nil
  defp render(segment, depth \\ 0)

  defp render("", _depth) do
    nil
  end

  defp render("\n", _depth) do
    # When this empty string is joined to surrounding code, it will end
    # up putting a newline in between, retaining whitespace from the user.
    ""
  end

  defp render(segment, depth) when is_binary(segment) do
    String.duplicate(@tab, depth) <> segment
  end

  defp render({tag, attributes, children}, depth) do
    self_closing = Enum.empty?(children)

    indentation = String.duplicate(@tab, depth)

    joined_attributes =
      case attributes do
        [] -> ""
        _ -> " " <> Enum.join(attributes, " ")
      end

    opening = "<" <> tag <> joined_attributes <> "#{if self_closing do " /" end}>"

    opening =
      if String.length(opening) > @max_line_length do
        indented_attributes =
          attributes
          |> Enum.map(&indent(&1, depth + 1))

        [
          "<#{tag}",
          indented_attributes,
          "#{indentation}#{if self_closing do "/" end}>"
        ]
        |> List.flatten()
        |> Enum.join("\n")
      else
        opening
      end

    rendered_children =
      children
      |> Enum.map(fn child ->
        # I don't understand what's going on with this behavior regarding macro
        # tags, but currently decreasing indentation depth by 3 seems to leave
        # the child contents alone.
        child_indent_depth = depth + if is_macro_tag?(tag) do -3 else 1 end
        render(child, child_indent_depth)
      end)
      |> List.flatten()
      # Remove nils
      |> Enum.filter(&Function.identity/1)
      |> Enum.join("\n")

    closing = "</#{tag}>"

    if self_closing do
      "#{indentation}#{opening}"
    else
      "#{indentation}#{opening}\n#{rendered_children}\n#{indentation}#{closing}"
    end
  end

  defp indent(string, depth) do
    indentation = String.duplicate(@tab, depth)

    # This is pretty hacky, but it's an attempt to get
    #   class={{
    #     "foo",
    #     @bar,
    #     baz: true
    #   }}
    # to look right
    string_with_newlines_indented = String.replace(string, "\n", "\n#{indentation}")

    "#{indentation}#{string_with_newlines_indented}"
  end

  defp is_macro_tag?("#" <> _), do: true
  defp is_macro_tag?(tag) when is_binary(tag), do: false
end
