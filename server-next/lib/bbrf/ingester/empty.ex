defmodule BBRF.Ingester.Empty do
  @moduledoc """
  Runs every EMPTY_MINUTES (default 60).
  """

  require Logger
  alias BBRF.Env

  def interval_minutes, do: Env.int("EMPTY_MINUTES", 60)

  @doc "One round. Never throws."
  def run do
    try do
      :ok
    rescue
      exception ->
        Logger.error("empty failed:\n" <> Exception.format(:error, exception, __STACKTRACE__))

        nil
    end
  end
end
