# radio-waybar - one-shot JSON status of the bbrf always-on radio,
# implementing waybar's custom module protocol:
#
#   {"text": ..., "class": "audible"|"muted"|"off", "tooltip": ...}
#
# Part of bbrf-radio: https://github.com/vhsconnect/bbrf-radio
#
# SOCKET and DEFAULT_STATION are prepended by nix/radio-waybar.nix and can
# be overridden through the environment. JQ and SOCAT are baked in at build
# time. Muting/unmuting is the `radio` CLI's job (`radio toggle`), not this
# script's.

function ipc
    printf '%s\n' $argv | $SOCAT - $SOCKET 2>/dev/null
end

function getMute
    set -l resp (ipc '{"command":["get_property","mute"]}')
    if test (count $resp) -eq 0
        echo unknown
        return
    end
    printf '%s\n' $resp[1] | $JQ -r '.data | if . == null then "unknown" else tostring end'
end

function getTitle
    set -l resp (ipc '{"command":["get_property","media-title"]}')
    if test (count $resp) -eq 0
        return
    end
    printf '%s\n' $resp[1] | $JQ -r '.data // empty'
end

# station name as set by `radio station NAME`, empty if never switched
function getName
    set -l resp (ipc '{"command":["get_property","user-data/bbrf/name"]}')
    if test (count $resp) -eq 0
        return
    end
    printf '%s\n' $resp[1] | $JQ -r '.data // empty'
end

if not test -S $SOCKET
    $JQ -cn '{text:"", class:"off", tooltip:"radio not running"}'
    exit 0
end

set -l state audible
set -l label audible

if test (getMute) = true
    set state muted
    set label muted
end

set -l title (getTitle)
set -l station (getName)
if test -z "$station"
    set station $DEFAULT_STATION
end

# song title in the bar itself, station name as fallback
set -l text $station
if test -n "$title"
    set text $title
end

if test (string length $text) -gt 40
    set text (string sub -l 39 $text)"…"
end

set -l tooltip "bbrf radio: $label"
if test -n "$title"
    set tooltip "$tooltip\n$station\n$title"
end

$JQ -cn --arg t "$text" --arg c $state --arg T "$tooltip" '{text:$t, class:$c, tooltip:$T}'
