defmodule AshGrant.PolicyTest.Result do
  @moduledoc """
  Represents the result of a single policy test execution.

  ## Fields

  - `:test_name` - The full name of the test
  - `:passed` - Whether the test passed (true) or failed (false)
  - `:message` - Error message if the test failed, nil if passed
  - `:duration_us` - Execution time in microseconds
  - `:module` - The module containing this test (optional, set by `run_all`)
  """

  @type t :: %__MODULE__{
          test_name: String.t(),
          passed: boolean(),
          message: String.t() | nil,
          duration_us: non_neg_integer(),
          module: module() | nil
        }

  defstruct [:test_name, :passed, :message, :duration_us, :module]

  @doc """
  Creates a new Result for a passed test.
  """
  @spec pass(String.t(), non_neg_integer()) :: t()
  def pass(test_name, duration_us) do
    %__MODULE__{
      test_name: test_name,
      passed: true,
      message: nil,
      duration_us: duration_us
    }
  end

  @doc """
  Creates a new Result for a failed test.
  """
  @spec fail(String.t(), String.t(), non_neg_integer()) :: t()
  def fail(test_name, message, duration_us) do
    %__MODULE__{
      test_name: test_name,
      passed: false,
      message: message,
      duration_us: duration_us
    }
  end
end
