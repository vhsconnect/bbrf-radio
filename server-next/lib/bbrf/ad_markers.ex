defmodule BBRF.AdMarkers do
  @moduledoc """
  Recognizes the titles stations send during ad breaks, from what
  production streams were seen to send: Live365's "Advertisement",
  iHeart's `song_spot="T"` spots and "Spot Block End", AdsWizz's
  `adw_ad:true` midrolls, and the local words for an ad ("Reklama",
  "Werbung in SWR1", "PUBBLICITA'", ...).

  The words only match whole, so songs like "Advertising Space" or
  "Die Reklamation" are not ads. `adw_ad:` alone is not a marker: AdsWizz
  streams prefix music with it too.
  """

  @markers [
    ~r/song_spot="T"/,
    ~r/digitalAds="yes"/i,
    ~r/adw_ad:true/i,
    ~r/spot block/i,
    ~r/^spot\b/i,
    ~r/(?<![a-z])ad[ _-]?break/i,
    ~r/(commercial|advert) break/i,
    ~r/after this break/i,
    ~r/corte (comercial|publicitario)/i,
    ~r/(tanda|espacio) publicitari[ao]/i,
    ~r/\b(advert|advertisement)\b/iu,
    ~r/\b(reklama|reklame|reclame|werbung)\b/iu,
    ~r/\bpubblicit(a|à|á|&agrave;)/iu,
    ~r/\b(publicitate|publicidad|publicité|publicite|publiciteit)\b/iu
  ]

  @spec ad?(String.t() | nil) :: boolean()
  def ad?(nil), do: false
  def ad?(raw_title), do: Enum.any?(@markers, &Regex.match?(&1, raw_title))
end
