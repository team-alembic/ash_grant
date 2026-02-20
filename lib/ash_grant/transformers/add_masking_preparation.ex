defmodule AshGrant.Transformers.AddMaskingPreparation do
  @moduledoc """
  Adds the masking preparation to resources that have field groups with masking.

  When any field group defines `mask` and `mask_with`, this transformer adds
  `AshGrant.Preparations.ApplyMasking` as a resource-level preparation for
  read actions. The preparation applies masked values at runtime based on
  the actor's field group level.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: true

  @impl true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    field_groups = get_field_group_entities(dsl_state)
    has_masking? = Enum.any?(field_groups, &has_masking?/1)

    if has_masking? do
      add_masking_preparation(dsl_state)
    else
      {:ok, dsl_state}
    end
  end

  defp has_masking?(%{mask: mask, mask_with: mask_with})
       when is_list(mask) and mask != [] and not is_nil(mask_with),
       do: true

  defp has_masking?(_), do: false

  defp add_masking_preparation(dsl_state) do
    preparation = %Ash.Resource.Preparation{
      preparation: {AshGrant.Preparations.ApplyMasking, []},
      on: [:read]
    }

    {:ok, Transformer.add_entity(dsl_state, [:preparations], preparation, type: :append)}
  end

  defp get_field_group_entities(dsl_state) do
    Transformer.get_entities(dsl_state, [:ash_grant])
    |> Enum.filter(&match?(%AshGrant.Dsl.FieldGroup{}, &1))
  end
end
