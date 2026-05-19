if Code.ensure_loaded?(Clarity) and Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule AshGrant.Clarity.Content.ActorExplorerTest do
    @moduledoc """
    Behavioural tests for the interactive actor explorer LiveView.

    Rendering is covered indirectly — we assert that `applies?/2` admits the
    right vertices and that the `handle_event/3` callbacks interact with
    `AshGrant.Introspect` in the expected way by constructing a socket by
    hand and calling the callbacks directly. This avoids pulling in a full
    Phoenix endpoint/router just to exercise the logic.
    """
    use ExUnit.Case, async: true

    alias AshGrant.Clarity.Content.ActorExplorer
    alias AshGrant.Explanation
    alias Clarity.Vertex.Ash.Resource, as: ResourceVertex
    alias Phoenix.LiveView.Socket

    @id_loadable %ResourceVertex{resource: AshGrant.Test.IdLoadablePost}
    @no_load_actor %ResourceVertex{resource: AshGrant.Test.NoLoadActorPost}

    describe "applies?/2" do
      test "true for AshGrant resources" do
        assert ActorExplorer.applies?(@id_loadable, fake_lens())
      end

      test "false for non-AshGrant resources" do
        refute ActorExplorer.applies?(%ResourceVertex{resource: String}, fake_lens())
      end
    end

    describe "mount/3" do
      test "assigns resource, resource_key, actions and :ready resolver status" do
        {:ok, socket} =
          ActorExplorer.mount(:ignored, %{"vertex" => @id_loadable}, build_socket())

        assert socket.assigns.resource == AshGrant.Test.IdLoadablePost
        assert socket.assigns.resource_key == "id_loadable_post"
        assert socket.assigns.resolver_status == :ready
        assert is_list(socket.assigns.actions)
      end

      test "flags resolver that does not implement load_actor/1" do
        {:ok, socket} =
          ActorExplorer.mount(:ignored, %{"vertex" => @no_load_actor}, build_socket())

        assert socket.assigns.resolver_status == :no_load_actor
      end
    end

    describe "handle_event/3 lookup" do
      test "populates permissions for a known actor id" do
        {:ok, socket} =
          ActorExplorer.mount(:ignored, %{"vertex" => @id_loadable}, build_socket())

        assert {:noreply, socket} =
                 ActorExplorer.handle_event("lookup", %{"actor_id" => "user_1"}, socket)

        assert is_list(socket.assigns.permissions)
        assert socket.assigns.lookup_error == nil

        perm = Enum.find(socket.assigns.permissions, &(&1.action == "read"))
        assert perm.allowed
      end

      test "reports :actor_not_found for unknown ids" do
        {:ok, socket} =
          ActorExplorer.mount(:ignored, %{"vertex" => @id_loadable}, build_socket())

        assert {:noreply, socket} =
                 ActorExplorer.handle_event("lookup", %{"actor_id" => "ghost"}, socket)

        assert socket.assigns.lookup_error == :actor_not_found
      end

      test "reports :actor_loader_not_implemented for resolvers without load_actor/1" do
        {:ok, socket} =
          ActorExplorer.mount(:ignored, %{"vertex" => @no_load_actor}, build_socket())

        assert {:noreply, socket} =
                 ActorExplorer.handle_event("lookup", %{"actor_id" => "user_1"}, socket)

        assert socket.assigns.lookup_error == :actor_loader_not_implemented
      end
    end

    describe "handle_event/3 explain" do
      test "populates an Explanation struct for an allowed action" do
        {:ok, socket} =
          ActorExplorer.mount(:ignored, %{"vertex" => @id_loadable}, build_socket())

        {:noreply, socket} =
          ActorExplorer.handle_event("lookup", %{"actor_id" => "user_1"}, socket)

        assert {:noreply, socket} =
                 ActorExplorer.handle_event("explain", %{"action" => "read"}, socket)

        assert %Explanation{action: :read, decision: :allow} = socket.assigns.explain
        assert socket.assigns.selected_action == :read
      end

      test "flags :unknown_action when the action string does not match an atom" do
        {:ok, socket} =
          ActorExplorer.mount(:ignored, %{"vertex" => @id_loadable}, build_socket())

        assert {:noreply, socket} =
                 ActorExplorer.handle_event(
                   "explain",
                   %{"action" => "not_a_real_action_name_#{System.unique_integer()}"},
                   socket
                 )

        assert socket.assigns.explain == nil
        assert socket.assigns.explain_error == :unknown_action
      end
    end

    defp build_socket do
      %Socket{
        assigns: %{__changed__: %{}, flash: %{}}
      }
    end

    defp fake_lens, do: %{id: "test"}
  end
end
