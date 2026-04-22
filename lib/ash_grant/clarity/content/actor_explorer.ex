with {:module, _} <- Code.ensure_loaded(Clarity),
     {:module, _} <- Code.ensure_loaded(Ash),
     {:module, _} <- Code.ensure_loaded(Phoenix.LiveView) do
  defmodule AshGrant.Clarity.Content.ActorExplorer do
    @moduledoc """
    Interactive LiveView content provider for exploring AshGrant permissions
    as a specific actor.

    Given an actor id the view calls
    `AshGrant.Introspect.actor_permissions_by_id/3` to show every action on
    the resource with its allow/deny status, scope, and field groups. Clicking
    *Explain* on a row calls `AshGrant.Introspect.explain_by_identifier/1` and
    renders the full `AshGrant.Explanation.to_string/2` output.

    Errors from the resolver (`:unknown_resource`,
    `:actor_loader_not_implemented`, `:actor_not_found`) surface as inline
    warning banners with remediation guidance.
    """

    use Phoenix.LiveView

    @behaviour Clarity.Content

    alias AshGrant.Clarity.Vertex.Scope, as: ScopeVertex
    alias AshGrant.Explanation
    alias AshGrant.Info
    alias AshGrant.Introspect
    alias Clarity.Vertex.Ash.Resource, as: ResourceVertex

    @impl Clarity.Content
    def name, do: "Actor Explorer"

    @impl Clarity.Content
    def description, do: "Interactive permission exploration for a given actor"

    @impl Clarity.Content
    def sort_priority, do: -40

    @impl Clarity.Content
    def applies?(%ResourceVertex{resource: resource}, _lens), do: uses_ash_grant?(resource)
    def applies?(_vertex, _lens), do: false

    defp uses_ash_grant?(resource) do
      AshGrant in Spark.extensions(resource)
    rescue
      _ -> false
    end

    @impl Phoenix.LiveView
    def mount(_params, session, socket) do
      %ResourceVertex{resource: resource} = session["vertex"]

      resource_key = Info.resource_name(resource)
      actions = Ash.Resource.Info.actions(resource)
      resolver = Info.resolver(resource)

      {:ok,
       socket
       |> assign(
         resource: resource,
         resource_key: resource_key,
         actions: actions,
         resolver: resolver,
         resolver_status: resolver_status(resolver),
         actor_id: "",
         permissions: nil,
         lookup_error: nil,
         explain: nil,
         explain_error: nil,
         selected_action: nil
       )}
    end

    @impl Phoenix.LiveView
    def handle_event("lookup", %{"actor_id" => actor_id}, socket) do
      actor_id = String.trim(actor_id)
      resource_key = socket.assigns.resource_key

      socket =
        if actor_id == "" do
          assign(socket,
            actor_id: "",
            permissions: nil,
            lookup_error: :blank_actor_id,
            explain: nil,
            explain_error: nil,
            selected_action: nil
          )
        else
          case Introspect.actor_permissions_by_id(actor_id, resource_key) do
            {:ok, permissions} ->
              assign(socket,
                actor_id: actor_id,
                permissions: permissions,
                lookup_error: nil,
                explain: nil,
                explain_error: nil,
                selected_action: nil
              )

            {:error, reason} ->
              assign(socket,
                actor_id: actor_id,
                permissions: nil,
                lookup_error: reason,
                explain: nil,
                explain_error: nil,
                selected_action: nil
              )
          end
        end

      {:noreply, socket}
    end

    def handle_event("explain", %{"action" => action_string}, socket) do
      %{actor_id: actor_id, resource_key: resource_key} = socket.assigns

      case safe_existing_atom(action_string) do
        {:ok, action} ->
          case Introspect.explain_by_identifier(
                 actor_id: actor_id,
                 resource_key: resource_key,
                 action: action
               ) do
            {:ok, explanation} ->
              {:noreply,
               assign(socket,
                 explain: explanation,
                 explain_error: nil,
                 selected_action: action
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 explain: nil,
                 explain_error: reason,
                 selected_action: action
               )}
          end

        :error ->
          {:noreply,
           assign(socket,
             explain: nil,
             explain_error: :unknown_action,
             selected_action: nil
           )}
      end
    end

    def handle_event("clear_explain", _params, socket) do
      {:noreply, assign(socket, explain: nil, explain_error: nil, selected_action: nil)}
    end

    defp safe_existing_atom(string) when is_binary(string) do
      {:ok, String.to_existing_atom(string)}
    rescue
      ArgumentError -> :error
    end

    defp resolver_status(nil), do: :missing
    defp resolver_status(fun) when is_function(fun, 2), do: :anonymous
    defp resolver_status(mod) when is_atom(mod) do
      Code.ensure_loaded(mod)
      if function_exported?(mod, :load_actor, 1), do: :ready, else: :no_load_actor
    end

    @impl Phoenix.LiveView
    def render(assigns) do
      ~H"""
      <div class="p-4 space-y-4 max-w-[120ch]">
        <header>
          <h2 class="text-lg font-semibold">Actor Explorer</h2>
          <p class="text-sm opacity-70">
            Resource <code>{inspect(@resource)}</code>
            (permission key <code>{@resource_key}</code>)
          </p>
        </header>

        <.resolver_banner status={@resolver_status} resolver={@resolver} />

        <form phx-submit="lookup" class="flex gap-2 items-end" :if={@resolver_status == :ready}>
          <label class="flex flex-col text-sm grow">
            <span class="font-medium">Actor id</span>
            <input
              type="text"
              name="actor_id"
              value={@actor_id}
              placeholder="e.g. user_123"
              class="border rounded px-2 py-1"
              autocomplete="off"
            />
          </label>
          <button type="submit" class="border rounded px-3 py-1 font-medium">
            Look up
          </button>
        </form>

        <.lookup_error_banner reason={@lookup_error} actor_id={@actor_id} />

        <section :if={@permissions}>
          <h3 class="font-semibold mb-2">Permissions for <code>{@actor_id}</code></h3>
          <.permissions_table permissions={@permissions} selected_action={@selected_action} />
        </section>

        <.explain_error_banner reason={@explain_error} />

        <section :if={@explain} class="space-y-2">
          <div class="flex items-center justify-between">
            <h3 class="font-semibold">
              Explain: <code>{@explain.action}</code>
              — <span class={decision_class(@explain.decision)}>{@explain.decision}</span>
            </h3>
            <button type="button" phx-click="clear_explain" class="text-sm underline opacity-70">
              close
            </button>
          </div>

          <p class="text-sm">{@explain.summary}</p>

          <details open>
            <summary class="cursor-pointer text-sm font-medium">Full explanation</summary>
            <pre class="text-xs whitespace-pre-wrap border rounded p-2 mt-2"><%= Explanation.to_string(@explain, color: false) %></pre>
          </details>
        </section>
      </div>
      """
    end

    # --- Embedded components -------------------------------------------------

    attr :status, :atom, required: true
    attr :resolver, :any, required: true

    defp resolver_banner(%{status: :ready} = assigns), do: ~H""

    defp resolver_banner(%{status: :missing} = assigns) do
      ~H"""
      <div class="border border-amber-500 rounded p-3 text-sm">
        <strong>No resolver configured.</strong>
        The resource has no <code>resolver</code> and no <code>grants</code>
        declared — the explorer has nothing to ask.
      </div>
      """
    end

    defp resolver_banner(%{status: :anonymous} = assigns) do
      ~H"""
      <div class="border border-amber-500 rounded p-3 text-sm">
        <strong>Resolver is an anonymous function.</strong>
        The explorer needs to load actors by id, which requires a module-based
        resolver with a <code>load_actor/1</code> callback. Convert the
        resolver to a module (implement
        <code>AshGrant.PermissionResolver</code>) to enable this view.
      </div>
      """
    end

    defp resolver_banner(%{status: :no_load_actor} = assigns) do
      ~H"""
      <div class="border border-amber-500 rounded p-3 text-sm">
        <strong>Resolver doesn't implement <code>load_actor/1</code>.</strong>
        Implement the optional <code>load_actor(actor_id)</code> callback on
        <code>{inspect(@resolver)}</code> — it should return a result tuple
        with the loaded actor or <code>:error</code>.
      </div>
      """
    end

    attr :reason, :any, required: true
    attr :actor_id, :string, required: true

    defp lookup_error_banner(%{reason: nil} = assigns), do: ~H""

    defp lookup_error_banner(%{reason: :blank_actor_id} = assigns) do
      ~H"""
      <div class="border border-amber-500 rounded p-3 text-sm">
        Enter an actor id to look up.
      </div>
      """
    end

    defp lookup_error_banner(%{reason: :actor_not_found} = assigns) do
      ~H"""
      <div class="border border-red-500 rounded p-3 text-sm">
        <strong>No actor found.</strong>
        The resolver returned <code>:error</code> for actor id
        <code>{@actor_id}</code>.
      </div>
      """
    end

    defp lookup_error_banner(%{reason: :actor_loader_not_implemented} = assigns) do
      ~H"""
      <div class="border border-red-500 rounded p-3 text-sm">
        <strong>Resolver cannot load actors.</strong>
        Implement <code>load_actor/1</code> on the resolver module.
      </div>
      """
    end

    defp lookup_error_banner(%{reason: :unknown_resource} = assigns) do
      ~H"""
      <div class="border border-red-500 rounded p-3 text-sm">
        <strong>Unknown resource.</strong>
        Could not resolve the resource key — this usually indicates a
        compile-time ordering problem.
      </div>
      """
    end

    defp lookup_error_banner(%{reason: other} = assigns) when not is_nil(other) do
      assigns = Map.put(assigns, :detail, inspect(other))

      ~H"""
      <div class="border border-red-500 rounded p-3 text-sm">
        <strong>Lookup failed:</strong> <code>{@detail}</code>
      </div>
      """
    end

    attr :reason, :any, required: true

    defp explain_error_banner(%{reason: nil} = assigns), do: ~H""

    defp explain_error_banner(%{reason: :unknown_action} = assigns) do
      ~H"""
      <div class="border border-amber-500 rounded p-3 text-sm">
        Could not resolve the action name.
      </div>
      """
    end

    defp explain_error_banner(%{reason: other} = assigns) do
      assigns = Map.put(assigns, :detail, inspect(other))

      ~H"""
      <div class="border border-red-500 rounded p-3 text-sm">
        <strong>Explain failed:</strong> <code>{@detail}</code>
      </div>
      """
    end

    attr :permissions, :list, required: true
    attr :selected_action, :any, required: true

    defp permissions_table(assigns) do
      ~H"""
      <table class="w-full text-sm border-collapse">
        <thead>
          <tr class="border-b">
            <th class="text-left p-1">Action</th>
            <th class="text-left p-1">Status</th>
            <th class="text-left p-1">Scope</th>
            <th class="text-left p-1">Instance ids</th>
            <th class="text-left p-1">Field groups</th>
            <th class="text-left p-1"></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={perm <- @permissions}
            class={["border-b", @selected_action && to_string(@selected_action) == perm.action && "bg-blue-50"]}
          >
            <td class="p-1"><code>{perm.action}</code></td>
            <td class={["p-1", status_class(perm)]}>{status_label(perm)}</td>
            <td class="p-1">{scope_cell(perm.scope)}</td>
            <td class="p-1">{list_cell(perm.instance_ids)}</td>
            <td class="p-1">{list_cell(perm.field_groups)}</td>
            <td class="p-1">
              <button
                type="button"
                phx-click="explain"
                phx-value-action={perm.action}
                class="underline text-xs"
              >
                explain
              </button>
            </td>
          </tr>
        </tbody>
      </table>
      """
    end

    defp status_label(%{denied: true}), do: "denied"
    defp status_label(%{allowed: true}), do: "allowed"
    defp status_label(_), do: "no access"

    defp status_class(%{denied: true}), do: "text-red-600 font-medium"
    defp status_class(%{allowed: true}), do: "text-green-700 font-medium"
    defp status_class(_), do: "opacity-60"

    defp scope_cell(nil), do: "—"
    defp scope_cell(scope) when is_binary(scope), do: Phoenix.HTML.raw(["<code>", scope, "</code>"])

    defp list_cell(nil), do: "—"
    defp list_cell([]), do: "—"

    defp list_cell(list) when is_list(list) do
      Enum.map_join(list, ", ", &to_string/1)
    end

    defp decision_class(:allow), do: "text-green-700"
    defp decision_class(:deny), do: "text-red-600"
    defp decision_class(_), do: ""

    # Suppress "unused" warnings when the module compiles conditionally.
    _ = ScopeVertex
  end
end
