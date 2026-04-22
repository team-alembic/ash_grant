with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Vertex.Grant do
    @moduledoc """
    Clarity graph vertex for an AshGrant grant — resource-local or inherited
    from a domain.
    """

    alias AshGrant.Dsl.Grant, as: GrantEntity

    @type owner :: module()

    @type t :: %__MODULE__{
            owner: owner(),
            owner_kind: :resource | :domain,
            grant: GrantEntity.t()
          }

    @enforce_keys [:owner, :owner_kind, :grant]
    defstruct [:owner, :owner_kind, :grant]

    defimpl Clarity.Vertex do
      alias Clarity.Vertex.Util

      @impl Clarity.Vertex
      def id(%@for{owner: owner, grant: grant}),
        do: Util.id(@for, [owner, grant.name])

      @impl Clarity.Vertex
      def type_label(_vertex), do: "AshGrant Grant"

      @impl Clarity.Vertex
      def name(%@for{grant: grant}), do: Atom.to_string(grant.name)
    end

    defimpl Clarity.Vertex.GraphGroupProvider do
      @impl Clarity.Vertex.GraphGroupProvider
      def graph_group(%@for{owner: owner}),
        do: [inspect(owner), "AshGrant Grants"]
    end

    defimpl Clarity.Vertex.GraphShapeProvider do
      @impl Clarity.Vertex.GraphShapeProvider
      def shape(_vertex), do: "folder"
    end

    defimpl Clarity.Vertex.SourceLocationProvider do
      alias Clarity.SourceLocation

      @impl Clarity.Vertex.SourceLocationProvider
      def source_location(%@for{owner: owner, grant: grant}) do
        SourceLocation.from_spark_entity(owner, grant)
      end
    end

    defimpl Clarity.Vertex.TooltipProvider do
      alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex

      @impl Clarity.Vertex.TooltipProvider
      def tooltip(%@for{owner: owner, owner_kind: kind, grant: grant}) do
        [
          "**AshGrant Grant** `:",
          Atom.to_string(grant.name),
          "`\n\n",
          describe_owner(kind, owner),
          grant_description(grant),
          "**Predicate:** `",
          ScopeVertex.render_filter(grant.predicate),
          "`\n\n",
          permissions_section(grant)
        ]
      end

      defp describe_owner(:resource, owner),
        do: ["On resource `", inspect(owner), "`\n\n"]

      defp describe_owner(:domain, owner),
        do: ["On domain `", inspect(owner), "` (inherited by resources)\n\n"]

      defp grant_description(%{description: desc}) when is_binary(desc) and desc != "",
        do: [desc, "\n\n"]

      defp grant_description(_), do: []

      defp permissions_section(%{permissions: perms}) when is_list(perms) and perms != [] do
        [
          "**Permissions:**\n\n",
          Enum.map(perms, fn perm ->
            [
              "- `",
              format_permission(perm),
              "`\n"
            ]
          end)
        ]
      end

      defp permissions_section(_), do: []

      defp format_permission(perm) do
        deny_prefix = if perm.deny, do: "!", else: ""

        on =
          case perm.on do
            nil -> "<self>"
            mod -> inspect(mod)
          end

        instance =
          case perm.instance do
            :* -> "*"
            nil -> "*"
            other -> to_string(other)
          end

        action = to_string(perm.action)

        scope =
          case perm.scope do
            nil -> ""
            scope_name -> Atom.to_string(scope_name)
          end

        Enum.join([deny_prefix, on, ":", instance, ":", action, ":", scope])
      end
    end
  end
end
