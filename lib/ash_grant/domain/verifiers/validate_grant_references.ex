defmodule AshGrant.Domain.Verifiers.ValidateGrantReferences do
  @moduledoc """
  Verifies each `permission` declared in a domain's `grants` block.

  Domain permissions are broadcasts — they apply to every resource in
  the domain — so the action and scope are validated against **every**
  resource the domain knows about (read directly from the domain's
  `resources do ... end` block).

  Validation rules per permission:

  - `action == :*` is always accepted (means "every action").
  - `action: :foo` must be defined on every resource in the domain.
  - `scope == nil` is always accepted (means "no row filter").
  - `scope: :foo` must resolve on every resource — that is, declared
    on the resource itself or inherited from this domain. The merged
    list comes from `AshGrant.Info.scopes/1`.

  By the time this verifier runs, every resource declared in the
  domain's `resources do` block is already compiled (Spark's
  `{:spark, Ash.Resource}` type for the `resource` entity establishes
  the compile-time dependency). We trust that invariant and read each
  resource's actions/scopes directly — no fallback for unloaded
  modules.
  """

  use Spark.Dsl.Verifier

  alias AshGrant.Verifiers.GrantTraversal
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    domain = Verifier.get_persisted(dsl_state, :module)
    grants = Verifier.get_entities(dsl_state, [:ash_grant, :grants])

    case grants do
      [] ->
        :ok

      _ ->
        resources = domain_resources(dsl_state)

        GrantTraversal.each_permission(grants, fn permission, grant ->
          validate_permission(permission, grant, domain, resources)
        end)
    end
  end

  defp domain_resources(dsl_state) do
    Verifier.get_entities(dsl_state, [:resources])
    |> Enum.map(& &1.resource)
  end

  defp validate_permission(permission, grant, domain, resources) do
    path = [:ash_grant, :grants, :grant, grant.name, :permission, permission.name]

    Enum.reduce_while(resources, :ok, fn resource, :ok ->
      case validate_against(permission, resource, domain, path) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_against(permission, resource, domain, path) do
    with :ok <- validate_action(permission, resource, domain, path) do
      validate_scope(permission, resource, domain, path)
    end
  end

  defp validate_action(%{action: :*}, _resource, _domain, _path), do: :ok

  defp validate_action(%{action: action}, resource, domain, path) when is_atom(action) do
    actions = resource |> Ash.Resource.Info.actions() |> Enum.map(& &1.name)

    if action in actions do
      :ok
    else
      dsl_error(
        domain,
        path,
        "`action: #{inspect(action)}` is not defined on #{inspect(resource)}. " <>
          "A domain-level permission applies to every resource in the domain — " <>
          "either add the action to #{inspect(resource)}, or move this permission " <>
          "to the resources where it belongs. Available actions on " <>
          "#{inspect(resource)}: #{inspect(actions)}."
      )
    end
  end

  defp validate_scope(%{scope: nil}, _resource, _domain, _path), do: :ok

  defp validate_scope(%{scope: scope}, resource, domain, path) when is_atom(scope) do
    scopes = resource |> AshGrant.Info.scopes() |> Enum.map(& &1.name)

    if scope in scopes do
      :ok
    else
      dsl_error(
        domain,
        path,
        "`scope: #{inspect(scope)}` is not defined on #{inspect(resource)} " <>
          "(or inherited from #{inspect(domain)}). A domain-level permission " <>
          "applies to every resource in the domain — declare " <>
          "`scope #{inspect(scope)}, expr(...)` on #{inspect(domain)} (so every " <>
          "resource inherits it) or on #{inspect(resource)} directly. " <>
          "Available scopes on #{inspect(resource)}: #{inspect(scopes)}."
      )
    end
  end

  defp dsl_error(domain, path, message) do
    {:error, DslError.exception(module: domain, path: path, message: message)}
  end
end
