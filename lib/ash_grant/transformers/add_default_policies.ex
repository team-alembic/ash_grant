defmodule AshGrant.Transformers.AddDefaultPolicies do
  @moduledoc """
  Spark DSL transformer that auto-generates policies when `default_policies` is enabled.

  This transformer runs at compile time and automatically generates the standard
  AshGrant policy configuration, reducing boilerplate for common use cases.

  ## Configuration

  Enable in your resource's `ash_grant` block:

      ash_grant do
        resolver MyApp.PermissionResolver
        default_policies true  # or :all, :read, :write
      end

  ## Options

  | Value | Description |
  |-------|-------------|
  | `false` | No policies generated (default) |
  | `true` or `:all` | Generate read, write, and generic action policies |
  | `:read` | Only generate `filter_check()` policy for read actions |
  | `:write` | Only generate `check()` policy for write and generic actions |

  ## Generated Policies

  When `default_policies: true` or `:all`:

      policies do
        policy action_type(:read) do
          authorize_if AshGrant.filter_check()
        end

        policy action_type([:create, :update, :destroy]) do
          authorize_if AshGrant.check()
        end

        policy action_type(:action) do
          authorize_if AshGrant.check()
        end
      end

  ## Implementation Details

  This transformer:
  - Runs **before** `Ash.Policy.Authorizer` to inject policies
  - Appends policies after user-defined ones so that user `bypass` policies take precedence
  - Sets appropriate `access_type` (`:filter` for read, `:strict` for write)

  ## See Also

  - `AshGrant.Check` - SimpleCheck for write actions
  - `AshGrant.FilterCheck` - FilterCheck for read actions
  - `AshGrant.Info.default_policies/1` - Query the setting at runtime
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(Ash.Policy.Authorizer), do: false
  def after?(_), do: true

  @impl true
  def before?(Ash.Policy.Authorizer), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    default_policies = Transformer.get_option(dsl_state, [:ash_grant], :default_policies, false)

    case default_policies do
      false ->
        {:ok, dsl_state}

      value when value in [true, :all] ->
        with {:ok, dsl_state} <- add_read_policy(dsl_state),
             {:ok, dsl_state} <- add_write_policy(dsl_state) do
          add_generic_action_policy(dsl_state)
        end

      :read ->
        add_read_policy(dsl_state)

      :write ->
        add_write_policy(dsl_state)
    end
  end

  defp add_read_policy(dsl_state) do
    read_policy = %Ash.Policy.Policy{
      bypass?: false,
      access_type: :filter,
      condition: [{Ash.Policy.Check.ActionType, type: [:read]}],
      policies: [
        %Ash.Policy.Check{
          type: :authorize_if,
          check_module: AshGrant.FilterCheck,
          check: {AshGrant.FilterCheck, []},
          check_opts: []
        }
      ]
    }

    {:ok, Transformer.add_entity(dsl_state, [:policies], read_policy, type: :append)}
  end

  defp add_write_policy(dsl_state) do
    # `create`/`update` use the strict `AshGrant.Check`:
    #   * create has no row yet, so the scope must be evaluated against the
    #     changeset's attributes — a FilterCheck has nothing to filter and the
    #     tenant/own scope would not be enforced (the create would leak).
    #   * update *could* be filter-based (it acts on a row), and that would be
    #     the better security posture (a filter hides non-matching rows instead
    #     of confirming existence via `Forbidden`) — but Ash's atomic-update
    #     forbidden path currently crashes (`Ash.Actions.Update.Bulk` calls
    #     `Ash.Authorizer.exception` with the authorizer module as a *string*,
    #     hitting `:erlang.function_exported/3`'s atom guard). The atomic-destroy
    #     path is not affected. Until that upstream Ash bug is fixed, update
    #     stays strict so an out-of-scope single update fails cleanly with
    #     `Forbidden` rather than an `ArgumentError`.
    strict_write_policy = %Ash.Policy.Policy{
      bypass?: false,
      access_type: :strict,
      condition: [{Ash.Policy.Check.ActionType, type: [:create, :update]}],
      policies: [
        %Ash.Policy.Check{
          type: :authorize_if,
          check_module: AshGrant.Check,
          check: {AshGrant.Check, []},
          check_opts: []
        }
      ]
    }

    # `destroy` uses `AshGrant.FilterCheck` (access_type :filter): the scope is
    # resolved to a filter that Ash evaluates against the target record for a
    # single destroy AND pushes into the query for a bulk/atomic destroy. The
    # strict SimpleCheck cannot authorize an atomic query destroy (it needs a
    # concrete record), so `cascade_destroy` — which prefers the atomic strategy
    # — would be forbidden. Filter-based authorization makes every destroy
    # strategy work uniformly (RBAC, instance, and `scope_through` scopes all
    # resolve to filters).
    filter_destroy_policy = %Ash.Policy.Policy{
      bypass?: false,
      access_type: :filter,
      condition: [{Ash.Policy.Check.ActionType, type: [:destroy]}],
      policies: [
        %Ash.Policy.Check{
          type: :authorize_if,
          check_module: AshGrant.FilterCheck,
          check: {AshGrant.FilterCheck, []},
          check_opts: []
        }
      ]
    }

    dsl_state = Transformer.add_entity(dsl_state, [:policies], strict_write_policy, type: :append)
    {:ok, Transformer.add_entity(dsl_state, [:policies], filter_destroy_policy, type: :append)}
  end

  defp add_generic_action_policy(dsl_state) do
    generic_policy = %Ash.Policy.Policy{
      bypass?: false,
      access_type: :strict,
      condition: [{Ash.Policy.Check.ActionType, type: [:action]}],
      policies: [
        %Ash.Policy.Check{
          type: :authorize_if,
          check_module: AshGrant.Check,
          check: {AshGrant.Check, []},
          check_opts: []
        }
      ]
    }

    {:ok, Transformer.add_entity(dsl_state, [:policies], generic_policy)}
  end
end
