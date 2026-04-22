with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash) do
  defmodule AshGrant.Clarity.Vertex.Scope do
    @moduledoc """
    Clarity graph vertex for an AshGrant scope — either resource-local or
    inherited from a domain.
    """

    alias AshGrant.Dsl.Scope, as: ScopeEntity

    @type owner :: module()

    @type t :: %__MODULE__{
            owner: owner(),
            owner_kind: :resource | :domain,
            scope: ScopeEntity.t()
          }

    @enforce_keys [:owner, :owner_kind, :scope]
    defstruct [:owner, :owner_kind, :scope]

    defimpl Clarity.Vertex do
      alias Clarity.Vertex.Util

      @impl Clarity.Vertex
      def id(%@for{owner: owner, scope: scope}),
        do: Util.id(@for, [owner, scope.name])

      @impl Clarity.Vertex
      def type_label(_vertex), do: "AshGrant Scope"

      @impl Clarity.Vertex
      def name(%@for{scope: scope}), do: Atom.to_string(scope.name)
    end

    defimpl Clarity.Vertex.GraphGroupProvider do
      @impl Clarity.Vertex.GraphGroupProvider
      def graph_group(%@for{owner: owner}),
        do: [inspect(owner), "AshGrant Scopes"]
    end

    defimpl Clarity.Vertex.GraphShapeProvider do
      @impl Clarity.Vertex.GraphShapeProvider
      def shape(_vertex), do: "note"
    end

    defimpl Clarity.Vertex.SourceLocationProvider do
      alias Clarity.SourceLocation

      @impl Clarity.Vertex.SourceLocationProvider
      def source_location(%@for{owner: owner, scope: scope}) do
        SourceLocation.from_spark_entity(owner, scope)
      end
    end

    defimpl Clarity.Vertex.TooltipProvider do
      alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex

      @impl Clarity.Vertex.TooltipProvider
      def tooltip(%@for{owner: owner, owner_kind: kind, scope: scope}) do
        [
          "**AshGrant Scope** `:",
          Atom.to_string(scope.name),
          "`\n\n",
          describe_owner(kind, owner),
          scope_description(scope),
          "**Filter:** `",
          ScopeVertex.render_filter(scope.filter),
          "`\n"
        ]
      end

      defp describe_owner(:resource, owner),
        do: ["On resource `", inspect(owner), "`\n\n"]

      defp describe_owner(:domain, owner),
        do: ["On domain `", inspect(owner), "` (inherited by resources)\n\n"]

      defp scope_description(%{description: desc}) when is_binary(desc) and desc != "",
        do: [desc, "\n\n"]

      defp scope_description(_), do: []
    end

    @doc """
    Renders a scope filter (boolean or `Ash.Expr`) into a short string suitable
    for tooltips and markdown tables.
    """
    @spec render_filter(boolean() | Ash.Expr.t()) :: String.t()
    def render_filter(true), do: "true"
    def render_filter(false), do: "false"

    def render_filter(expr) do
      AshGrant.ExprStringify.to_string(expr)
    rescue
      _ -> inspect(expr)
    end
  end
end
