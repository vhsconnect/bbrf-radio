defmodule BBRF.Metrics.Quality do
  @moduledoc """
  Sound quality as the MP3 bitrate that would sound as good, from the
  codec and bitrate radio-browser reports: AAC and Vorbis get more out of
  a kbps than MP3, HE-AAC (AAC+) more still, and FLAC is lossless, put at
  CD's 1411. NULL when the bitrate is unknown (0) or outside the 8-512
  kbps a lossy audio stream uses, and for video streams.

  Unlike the metrics `BBRF.Metrics.run/2` stores, it is read from the
  catalogue on every request, so it covers every station and follows the
  catalogue sync. `hi_qlty` sorts highest first and `lo_qlty` lowest first,
  both with the unknown last. `sample` is the reported bitrate.
  """

  @sorts [{"hi_qlty", "DESC"}, {"lo_qlty", "ASC"}]

  @mp3_kbps_per_kbps [{"AAC", 1.4}, {"AAC+", 2.0}, {"OGG", 1.3}]

  def names, do: Enum.map(@sorts, &elem(&1, 0))

  def direction(name), do: @sorts |> List.keyfind!(name, 0) |> elem(1)

  @doc "SQL for the quality of the `stations` row aliased `s`."
  def sql do
    factors =
      Enum.map_join(@mp3_kbps_per_kbps, " ", fn {codec, f} -> "WHEN '#{codec}' THEN #{f}" end)

    """
    CASE
      WHEN upper(s.codec) LIKE '%H.264%' OR upper(s.codec) IN ('MP4', 'FLV') THEN NULL
      WHEN upper(s.codec) = 'FLAC' THEN 1411.0
      WHEN s.bitrate BETWEEN 8 AND 512 THEN s.bitrate * CASE upper(s.codec) #{factors} ELSE 1.0 END
    END
    """
  end

  @doc "`stationuuids` in the catalogue, each with its quality under every name."
  def for_stations(stationuuids) do
    %{rows: rows} =
      BBRF.Repo.query!(
        """
        SELECT s.stationuuid, #{sql()}, s.bitrate
          FROM stations s
         WHERE s.stationuuid IN (SELECT value FROM json_each(?))
        """,
        [Jason.encode!(stationuuids)]
      )

    Map.new(rows, fn [stationuuid, value, bitrate] ->
      metric = %{"value" => value, "sample" => bitrate}
      {stationuuid, Map.new(names(), &{&1, metric})}
    end)
  end
end
