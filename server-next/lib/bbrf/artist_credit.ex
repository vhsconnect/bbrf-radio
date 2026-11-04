defmodule BBRF.ArtistCredit do
  @moduledoc """
  An artist credit is the artist string a station sends with a track, as
  parsed: one artist, several ("Ciara & Akeem Ali"), or junk (an ad, a
  placeholder). Its id is derived from the normalized string, so every
  node computes the same id for the same credit without a lookup: the
  ingester stamps it on each observation, and `BBRF.Ingester.Artists`
  later resolves it to MusicBrainz artists in `artist_credit_artists`.
  """

  @doc "The credit's matching key: NFC, lower case, whitespace collapsed."
  @spec normalize(String.t()) :: String.t()
  def normalize(name) do
    name
    |> :unicode.characters_to_nfc_binary()
    |> String.downcase()
    |> String.split()
    |> Enum.join(" ")
  end

  @doc "A non-negative 63-bit id from the normalized `name`; nil for no name."
  @spec id(String.t() | nil) :: non_neg_integer() | nil
  def id(nil), do: nil

  def id(name) do
    case normalize(name) do
      "" ->
        nil

      key ->
        <<_sign::1, id::63, _rest::bits>> = :crypto.hash(:sha256, key)
        id
    end
  end
end
