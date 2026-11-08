defmodule BBRF.Ingester.Artists.Cleanup do
  @moduledoc """
  Turns the artist and title a station sends into what
  `BBRF.Ingester.Artists` searches MusicBrainz with, and into the form
  its answer is compared in.

  The title only steers the search to a recording by the right artist,
  and no recording is stored, so `title/1` cuts it down hard. The artist
  is searched as loose words (`artist_terms/1`), since a station's
  punctuation and joiners rarely match MusicBrainz's; the guard against
  a wrong artist is the comparison of `fold/1`ed names afterwards.
  """

  @quotes ["’", "‘", "ʼ", "`", "´"]
  @joiners ~w(feat ft featuring vs x and with presents pres w)

  @brackets ~r/\s*[(\[{][^)\]}]*(?:[)\]}]|$)/u
  @separator ~r/\s+(?:-|–|—|\||\/\/?)\s+.*$/u
  @featuring ~r/\s+(?:feat\.?|ft\.|featuring|w\/)\s.*$/iu
  @url ~r/\s*(?:(?:https?:\/\/|www\.)\S*|\S+\.(?:com|net|org|info|fm|de|se|uk|nl|fr|it|es|ru|pl|tv|io)\b\S*)/iu
  @mix_tag ~r/\s+(?:\S+\s+)?(?:extended|radio|club|original|dub|vocal|instrumental)\s+(?:re)?mix\b.*$/iu
  @trailing ~r/[\s\-–—:;,.|\/]+$/u

  @doc """
  The comparison form of a name: compatibility characters and accents
  folded, lower case, `&` as "and", dots and apostrophes dropped, other
  punctuation as spaces, without a leading "the".

      fold("Guns N’ Roses") == fold("GUNS N' ROSES")  # "guns n roses"
  """
  @spec fold(String.t()) :: String.t()
  def fold(name), do: name |> plain() |> String.replace_prefix("the ", "")

  @doc "The words of a name folded as `fold/1` does, keeping a leading \"the\"."
  @spec words(String.t()) :: [String.t()]
  def words(name), do: name |> plain() |> String.split()

  defp plain(name) do
    name
    |> String.replace(@quotes, "'")
    |> :unicode.characters_to_nfkd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace("&", " and ")
    |> String.replace(~r/[.']/u, "")
    |> String.replace(~r/[^\p{L}\p{N}\p{M}]+/u, " ")
    |> String.trim()
  end

  @doc """
  The title without what stations add to it: bracketed parts (an
  unclosed one up to the end), anything after a spaced separator
  (`-`, `|`, `/`) or a featuring, urls, and a trailing mix tag. The
  title as sent when nothing would be left.
  """
  @spec title(String.t()) :: String.t()
  def title(title) do
    cleaned =
      title
      |> String.replace(@brackets, "")
      |> String.replace(@separator, "")
      |> String.replace(@featuring, "")
      |> String.replace(@url, "")
      |> String.replace(@mix_tag, "")
      |> String.replace(@trailing, "")
      |> String.trim()

    if cleaned =~ ~r/[\p{L}\p{N}]/u, do: cleaned, else: String.trim(title)
  end

  @doc """
  The words of a credit to search the artist field with: folded, so no
  Lucene syntax is left, and without joiners such as "feat" or "vs".
  """
  @spec artist_terms(String.t()) :: [String.t()]
  def artist_terms(name) do
    name |> fold() |> String.split() |> Enum.reject(&(&1 in @joiners))
  end
end
