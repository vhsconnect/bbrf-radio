defmodule BBRF.Metrics.Quality do
  @moduledoc """
  Sound quality as the MP3 bitrate that would sound as good, from the
  codec and bitrate radio-browser reports: AAC and Vorbis get more out of
  a kbps than MP3, HE-AAC (AAC+) more still, and FLAC is lossless, put at
  CD's 1411. NULL when the bitrate is unknown (0) or outside the 8-512
  kbps a lossy audio stream uses, and for video streams.

  `hi_qlty` sorts highest first and `lo_qlty` lowest first. `sample` is
  the reported bitrate.
  """

  @behaviour BBRF.Metrics.Catalogue

  @mp3_kbps_per_kbps [{"AAC", 1.4}, {"AAC+", 2.0}, {"OGG", 1.3}]

  @impl true
  def sorts, do: [{"hi_qlty", "DESC"}, {"lo_qlty", "ASC"}]

  @impl true
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

  @impl true
  def sample_sql, do: "s.bitrate"
end
