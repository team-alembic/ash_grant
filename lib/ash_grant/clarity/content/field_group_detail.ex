with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Content.FieldGroupDetail do
    @moduledoc """
    Static markdown detail page for an `AshGrant.Clarity.Vertex.FieldGroup`.
    """

    @behaviour Clarity.Content

    alias AshGrant.Clarity.Vertex.FieldGroup, as: FieldGroupVertex

    @impl Clarity.Content
    def name, do: "Field Group Detail"

    @impl Clarity.Content
    def description, do: "Details of this AshGrant field group"

    @impl Clarity.Content
    def sort_priority, do: -100

    @impl Clarity.Content
    def applies?(%FieldGroupVertex{}, _lens), do: true
    def applies?(_vertex, _lens), do: false

    @impl Clarity.Content
    def render_static(%FieldGroupVertex{} = vertex, _lens) do
      {:markdown, fn _props -> render(vertex) end}
    end

    defp render(%FieldGroupVertex{resource: resource, field_group: fg}) do
      resolved = resolve_fields_safe(resource, fg.name)

      [
        "# Field Group `:", Atom.to_string(fg.name), "`\n\n",
        "| Property | Value |\n",
        "| --- | --- |\n",
        "| **Resource** | `", inspect(resource), "` |\n",
        "| **Description** | ", escape_cell(fg.description || ""), " |\n",
        "| **Declared fields** | ", format_fields(fg), " |\n",
        "| **Inherits** | ", format_inherits(fg.inherits), " |\n",
        "| **Resolved fields** | ", format_field_list(resolved), " |\n",
        mask_row(fg),
        "\n"
      ]
    end

    defp resolve_fields_safe(resource, name) do
      case AshGrant.Info.resolve_field_group(resource, name) do
        %{fields: fields} -> fields
        nil -> nil
      end
    rescue
      _ -> :error
    end

    defp format_fields(%{fields: :all, except: except}) when is_list(except) and except != [] do
      [":all except ", field_atoms(except)]
    end

    defp format_fields(%{fields: :all}), do: ":all"

    defp format_fields(%{fields: fields}) when is_list(fields), do: field_atoms(fields)
    defp format_fields(_), do: ""

    defp format_inherits(nil), do: "*none*"
    defp format_inherits([]), do: "*none*"
    defp format_inherits(list) when is_list(list), do: field_atoms(list)

    defp format_field_list(:error), do: "*could not resolve*"
    defp format_field_list(nil), do: "*none*"
    defp format_field_list([]), do: "*none*"
    defp format_field_list([_ | _] = fields), do: field_atoms(fields)

    defp field_atoms(list),
      do: Enum.map_join(list, ", ", &("`:" <> Atom.to_string(&1) <> "`"))

    defp mask_row(%{mask: mask}) when is_list(mask) and mask != [] do
      [
        "| **Masked fields** | ",
        field_atoms(mask),
        " |\n"
      ]
    end

    defp mask_row(_), do: []

    defp escape_cell(value) when is_binary(value) do
      value
      |> String.replace("|", "\\|")
      |> String.replace("\n", " ")
    end

    defp escape_cell(value), do: escape_cell(to_string(value))
  end
end
