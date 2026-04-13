defmodule AshGrant.IntrospectRegistryTest do
  @moduledoc """
  Tests for Introspect resource registry: domain/resource discovery and
  key-based lookup.

  These functions are the foundation for external consumers
  (`ash_grant_phoenix`, `ash_grant_ai`) that need to enumerate resources
  or resolve a string key to a resource module without the caller knowing
  the module reference up-front.
  """
  use ExUnit.Case, async: true

  alias AshGrant.Introspect

  describe "list_domains/0" do
    test "returns domains configured via :ash_domains in started applications" do
      domains = Introspect.list_domains()

      # Test environment sets `config :ash_grant, ash_domains: [AshGrant.Test.Domain]`
      assert AshGrant.Test.Domain in domains
    end

    test "returns a unique list" do
      domains = Introspect.list_domains()
      assert domains == Enum.uniq(domains)
    end
  end

  describe "list_resources/1" do
    test "returns resources from auto-discovered domains" do
      resources = Introspect.list_resources()

      # Sampling of resources registered under AshGrant.Test.Domain
      assert AshGrant.Test.Post in resources
      assert AshGrant.Test.Employee in resources
      assert AshGrant.Test.SharedDoc in resources
    end

    test "every returned resource uses the AshGrant extension" do
      resources = Introspect.list_resources()

      Enum.each(resources, fn resource ->
        assert AshGrant in Spark.extensions(resource),
               "expected #{inspect(resource)} to use AshGrant extension"
      end)
    end

    test "accepts an explicit :domains option to restrict scope" do
      resources = Introspect.list_resources(domains: [AshGrant.Test.GrantDomain])

      # GrantDomain holds the Domain* resources and nothing else
      assert AshGrant.Test.DomainInheritedPost in resources
      refute AshGrant.Test.Post in resources
    end

    test "returns an empty list when no matching domains are given" do
      assert [] == Introspect.list_resources(domains: [])
    end

    test "returns a unique list" do
      resources = Introspect.list_resources()
      assert resources == Enum.uniq(resources)
    end
  end

  describe "find_resource_by_key/1" do
    test "resolves an explicit resource_name to its module" do
      # AshGrant.Test.Employee declares `resource_name("employee")`
      assert {:ok, AshGrant.Test.Employee} =
               Introspect.find_resource_by_key("employee")
    end

    test "resolves an auto-derived resource_name to its module" do
      # AshGrant.Test.Post has no explicit resource_name; derived as "post"
      assert {:ok, AshGrant.Test.Post} = Introspect.find_resource_by_key("post")
    end

    test "returns :error when no resource matches the key" do
      assert :error = Introspect.find_resource_by_key("definitely_not_a_resource")
    end

    test "returns :error for an empty string" do
      assert :error = Introspect.find_resource_by_key("")
    end

    test "matches are case-sensitive" do
      # "Employee" (capitalized) should not match "employee"
      assert :error = Introspect.find_resource_by_key("Employee")
    end
  end
end
