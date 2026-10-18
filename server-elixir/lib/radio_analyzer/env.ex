defmodule RadioAnalyzer.Env do
  @moduledoc """
  Configuration from environment variables, with the same names and
  defaults as the clojure original. Garbage values fall back to the
  default (like `parse-long` returning nil there).
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

  @doc "Opt-in flags, set to \"1\" (like VERBOSE=1 in the original)."
  @spec enabled?(String.t()) :: boolean()
  def enabled?(name), do: System.get_env(name) == "1"
end
