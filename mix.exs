defmodule AshGrant.MixProject do
  use Mix.Project

  @version "0.14.1"
  @source_url "https://github.com/jhlee111/ash_grant"

  def project do
    [
      app: :ash_grant,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      consolidate_protocols: Mix.env() != :test,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: "Permission-based authorization extension for Ash Framework",
      package: package(),

      # Docs
      name: "AshGrant",
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [
        clarity_introspectors: [
          AshGrant.Clarity.Introspector.Resource,
          AshGrant.Clarity.Introspector.Domain
        ],
        clarity_content_providers: [
          AshGrant.Clarity.Content.ResourceOverview,
          AshGrant.Clarity.Content.DomainOverview,
          AshGrant.Clarity.Content.ScopeDetail,
          AshGrant.Clarity.Content.GrantDetail,
          AshGrant.Clarity.Content.FieldGroupDetail,
          AshGrant.Clarity.Content.ActorExplorer
        ],
        clarity_perspective_lensmakers: [AshGrant.Clarity.Lensmaker]
      ]
    ]
  end

  defp deps do
    [
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:ash, ash_version("~> 3.19")},
      {:spark, spark_version("~> 2.0")},
      {:yaml_elixir, "~> 2.9", optional: true},

      # DB (test only)
      {:ash_postgres, "~> 2.0", only: :test},
      {:ecto_sql, "~> 3.10", only: :test},
      {:postgrex, "~> 0.17", only: :test},
      {:simple_sat, "~> 0.1", only: :test},

      # Dev/Test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0"}
    ] ++ clarity_deps()
  end

  # Optional Clarity integration — opt in via `CLARITY_VERSION` environment variable.
  #
  # The integration lives under `lib/ash_grant/clarity/` and every module is
  # wrapped in `Code.ensure_loaded(Clarity)` guards, so the library compiles
  # and runs normally whether or not Clarity is present. When consumers add
  # both `{:ash_grant, ...}` and `{:clarity, ...}` to their own mix.exs the
  # guards succeed and the integration activates automatically — they do not
  # need to set `CLARITY_VERSION`.
  #
  # `CLARITY_VERSION` is a development escape hatch so the AshGrant repo can
  # exercise the integration locally:
  #
  #     CLARITY_VERSION=local mix deps.get
  #     CLARITY_VERSION=main mix deps.get
  #     CLARITY_VERSION=0.4 mix deps.get
  defp clarity_deps do
    case System.get_env("CLARITY_VERSION") do
      nil ->
        []

      "local" ->
        path = System.get_env("CLARITY_LOCAL_PATH") || "../clarity"

        [
          {:clarity, path: path, optional: true},
          {:phoenix_live_view, "~> 1.0", optional: true}
        ]

      "main" ->
        [
          {:clarity, git: "https://github.com/team-alembic/clarity.git", optional: true},
          {:phoenix_live_view, "~> 1.0", optional: true}
        ]

      version ->
        [
          {:clarity, "~> #{version}", optional: true},
          {:phoenix_live_view, "~> 1.0", optional: true}
        ]
    end
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      name: "ash_grant",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md": [title: "Home"],
        "guides/getting-started.md": [title: "Getting Started"],
        "guides/authorization-patterns.md": [title: "RBAC / ABAC / ReBAC / More"],
        "guides/permissions.md": [title: "Permissions"],
        "guides/scopes.md": [title: "Scopes"],
        "guides/field-level-permissions.md": [title: "Field-Level Permissions"],
        "guides/scope-naming-convention.md": [title: "Scope Naming Convention"],
        "guides/argument-based-scope.md": [title: "Argument-Based Scope"],
        "guides/advanced-patterns.md": [title: "Advanced Patterns"],
        "guides/checks-and-policies.md": [title: "Checks & Policies"],
        "guides/debugging-and-introspection.md": [title: "Debugging & Introspection"],
        "guides/public-api-contract.md": [title: "Public API Contract"],
        "guides/policy-testing.md": [title: "Policy Testing"],
        "guides/migration.md": [title: "Migration Guide"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        Guides: ~r/guides\/.*/
      ]
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil -> default_version
      "local" -> [path: "../ash", override: true]
      "main" -> [git: "https://github.com/ash-project/ash.git", override: true]
      version -> "~> #{version}"
    end
  end

  defp spark_version(default_version) do
    case System.get_env("SPARK_VERSION") do
      nil -> default_version
      "local" -> [path: "../spark", override: true]
      "main" -> [git: "https://github.com/ash-project/spark.git", override: true]
      version -> "~> #{version}"
    end
  end

end
