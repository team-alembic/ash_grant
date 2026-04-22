with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Vertex.FieldGroup do
    @moduledoc """
    Clarity graph vertex for an AshGrant field group.

    Field groups are defined on resources (no domain-level inheritance today),
    so `owner_kind` is always `:resource`.
    """

    alias AshGrant.Dsl.FieldGroup, as: FieldGroupEntity

    @type t :: %__MODULE__{
            resource: module(),
            field_group: FieldGroupEntity.t()
          }

    @enforce_keys [:resource, :field_group]
    defstruct [:resource, :field_group]

    defimpl Clarity.Vertex do
      alias Clarity.Vertex.Util

      @impl Clarity.Vertex
      def id(%@for{resource: resource, field_group: fg}),
        do: Util.id(@for, [resource, fg.name])

      @impl Clarity.Vertex
      def type_label(_vertex), do: "AshGrant Field Group"

      @impl Clarity.Vertex
      def name(%@for{field_group: fg}), do: Atom.to_string(fg.name)
    end

    defimpl Clarity.Vertex.GraphGroupProvider do
      @impl Clarity.Vertex.GraphGroupProvider
      def graph_group(%@for{resource: resource}),
        do: [inspect(resource), "AshGrant Field Groups"]
    end

    defimpl Clarity.Vertex.GraphShapeProvider do
      @impl Clarity.Vertex.GraphShapeProvider
      def shape(_vertex), do: "box3d"
    end

    defimpl Clarity.Vertex.SourceLocationProvider do
      alias Clarity.SourceLocation

      @impl Clarity.Vertex.SourceLocationProvider
      def source_location(%@for{resource: resource, field_group: fg}) do
        SourceLocation.from_spark_entity(resource, fg)
      end
    end

    defimpl Clarity.Vertex.TooltipProvider do
      @impl Clarity.Vertex.TooltipProvider
      def tooltip(%@for{resource: resource, field_group: fg}) do
        [
          "**AshGrant Field Group** `:",
          Atom.to_string(fg.name),
          "`\n\n",
          "On resource `",
          inspect(resource),
          "`\n\n",
          description(fg),
          inherits_section(fg),
          fields_section(fg)
        ]
      end

      defp description(%{description: desc}) when is_binary(desc) and desc != "",
        do: [desc, "\n\n"]

      defp description(_), do: []

      defp inherits_section(%{inherits: inherits}) when is_list(inherits) and inherits != [] do
        [
          "**Inherits:** ",
          Enum.map_join(inherits, ", ", &("`:" <> Atom.to_string(&1) <> "`")),
          "\n\n"
        ]
      end

      defp inherits_section(_), do: []

      defp fields_section(%{fields: :all, except: except}) when is_list(except) and except != [] do
        [
          "**Fields:** all except ",
          Enum.map_join(except, ", ", &("`:" <> Atom.to_string(&1) <> "`")),
          "\n"
        ]
      end

      defp fields_section(%{fields: :all}), do: ["**Fields:** all\n"]

      defp fields_section(%{fields: fields}) when is_list(fields) do
        [
          "**Fields:** ",
          Enum.map_join(fields, ", ", &("`:" <> Atom.to_string(&1) <> "`")),
          "\n"
        ]
      end

      defp fields_section(_), do: []
    end
  end
end
