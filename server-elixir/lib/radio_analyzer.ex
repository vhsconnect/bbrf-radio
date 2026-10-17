defmodule RadioAnalyzer do
  @moduledoc """
  Long-running server that watches the Radio Browser "recently changed /
  recently clicked" endpoints for stations, then polls each station's
  icecast status page (`/status-json.xsl`) to record what track is
  playing. Elixir port of the clojure `radio-analyzer` service - see
  `RadioAnalyzer.Application` for the supervision tree and the project
  README for the wave design.
  """
end
