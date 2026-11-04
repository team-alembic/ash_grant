defmodule AshGrant.ScopeRegistry do
  @moduledoc """
  Config-level registry for scopes shared across every resource in an app.

  Resources that `use AshGrant` pick up registry scopes silently through
  `AshGrant.Info.scopes/1`, and can override a registry scope by declaring one
  of the same name in their own `ash_grant do` block. A domain with
  `AshGrant.Domain` can do the same. The precedence is:

      resource > domain > registry

  Same-name wins at each level.

  ## Example

      # lib/my_app/global_scopes.ex
      defmodule MyApp.GlobalScopes do
        use AshGrant.ScopeRegistry

        scope :always, true
        scope :own, expr(author_id == ^actor(:id))
        scope :same_tenant, expr(tenant_id == ^tenant())
      end

      # config/config.exs
      config :ash_grant, scope_registry: MyApp.GlobalScopes

  With that config, every resource that `use`s `AshGrant` sees `:always`,
  `:own`, and `:same_tenant` as if they had been declared on the resource,
  unless the resource (or its domain) declares a scope with the same name.

  ## Inheritance

  `scope :own_draft, [:own], expr(status == :draft)` is supported. Parents may
  be defined in the same registry, on the domain, or on the resource — the
  lookup still goes through `AshGrant.Info.get_scope/2`, which honours the
  precedence rule above. Keep inheritance chains shallow; a cycle is a
  programmer error and raises at runtime.

  ## Backwards compatibility

  If `:scope_registry` is not configured, the behaviour of `AshGrant.Info` is
  identical to earlier versions.
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import AshGrant.ScopeRegistry, only: [scope: 2, scope: 3]
      import Ash.Expr
      Module.register_attribute(__MODULE__, :ash_grant_registry_scopes, accumulate: true)
      @before_compile AshGrant.ScopeRegistry
    end
  end

  @doc """
  Declares a scope with a filter expression.

      scope :own, expr(author_id == ^actor(:id))
      scope :always, true
  """
  defmacro scope(name, filter) do
    quote do
      @ash_grant_registry_scopes %AshGrant.Dsl.Scope{
        name: unquote(name),
        inherits: nil,
        filter: unquote(filter),
        write: nil,
        description: nil
      }
    end
  end

  @doc """
  Declares a scope that inherits from one or more parent scopes.

      scope :own_draft, [:own], expr(status == :draft)
  """
  defmacro scope(name, inherits, filter) do
    quote do
      @ash_grant_registry_scopes %AshGrant.Dsl.Scope{
        name: unquote(name),
        inherits: unquote(inherits),
        filter: unquote(filter),
        write: nil,
        description: nil
      }
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      @spec __scopes__() :: %{atom() => AshGrant.Dsl.Scope.t()}
      def __scopes__ do
        @ash_grant_registry_scopes
        |> Enum.reverse()
        |> Map.new(&{&1.name, &1})
      end
    end
  end

  @doc """
  Returns the configured registry scopes as a list, or `[]` when no registry
  is configured.
  """
  @spec scopes() :: [AshGrant.Dsl.Scope.t()]
  def scopes do
    case Application.get_env(:ash_grant, :scope_registry) do
      nil ->
        []

      module when is_atom(module) ->
        try do
          module.__scopes__() |> Map.values()
        rescue
          UndefinedFunctionError -> []
        end
    end
  end
end
