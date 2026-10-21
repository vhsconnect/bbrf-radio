defmodule BBRF.Env do
  @moduledoc """
  Configuration from environment variables. Garbage values in `int/2`
  fall back to the default.
  """

  @spec int(String.t(), integer()) :: integer()
  def int(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {parsed, _rest} -> parsed
          :error -> default
        end
    end
  end

  @spec str(String.t(), String.t()) :: String.t()
  def str(name, default), do: System.get_env(name) || default

  @doc """
  On/off flag: "1" is on, "0" is off, unset uses the default. Anything
  else raises at boot, so a typo cannot silently pick a side.
  """
  @spec flag(String.t(), boolean()) :: boolean()
  def flag(name, default) do
    case System.get_env(name) do
      nil -> default
      "1" -> true
      "0" -> false
      other -> raise ArgumentError, "#{name} must be 1 or 0, got #{inspect(other)}"
    end
  end
end
