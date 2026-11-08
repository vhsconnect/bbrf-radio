defmodule BBRF.AdMarkersTest do
  use ExUnit.Case, async: true

  alias BBRF.AdMarkers

  @ads [
    ~s(- text="Spot Block End" amgTrackId="9876543" length="00:00:00"),
    ~s(- text="FRIENDLY FORD" song_spot="T" spotInstanceId="51622302" length="00:00:30"),
    "Live365 - Live365 - Advertisement",
    "Advert: - Advert:",
    "THIS STATION WILL CONTINUE AFTER THIS BREAK",
    "ADBREAK_END",
    "STOP_AD_BREAK",
    "Ad break",
    "adw_ad:true;durationMilliseconds:30000;insertionType:midroll;rand:104967",
    "Reklama",
    "Werbung in SWR1",
    "PUBBLICITA'",
    "KissFM - Publicitate",
    "INTRO AL CORTE COMERCIAL - INTRO CORTE PUBLICITARIO",
    "SPOT 5 (OTTOBRE 23)"
  ]

  @music [
    "Robbie Williams - Advertising Space",
    "Vintage Advertisements",
    "Wir Sind Helden - Guten Tag (Die Reklamation)",
    "Matthew Wilder - Break My Stride",
    "Ava Max - Spot A Fake",
    "Jennifer Hudson - Spotlight",
    ~s(Ariana Grande - text="Petal" song_spot="M" MediaBaseId="3246947"),
    "adw_ad:NATALIA LAFOURCADE;durationMilliseconds:180000;artist:NATALIA LAFOURCADE;title:HASTA LA RAIZ;album:",
    nil
  ]

  test "recognizes the ad breaks production streams send" do
    assert Enum.reject(@ads, &AdMarkers.ad?/1) == []
  end

  test "leaves songs named like a marker alone" do
    assert Enum.filter(@music, &AdMarkers.ad?/1) == []
  end
end
