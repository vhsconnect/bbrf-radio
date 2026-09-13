
# radio - control the bbrf always-on radio via mpv's IPC interface.
# Part of bbrf-radio: https://github.com/vhsconnect/bbrf-radio
#
#   radio on             un-mute
#   radio off            mute
#   radio toggle         flip mute
#   radio status         show mute state and current station
#   radio stations       list station names from bbrf favorites
#   radio station NAME   switch to station NAME (looked up in bbrf favorites)
#   radio pick           browse stations with rofi and switch to the choice
#
# SOCKET, PORT, DEFAULT_STATION, CURL, JQ, SOCAT and SORT are prepended
# by nix/module.nix (services.bbrf.alwaysOnRadio).

function requireSocket
    if not test -S $SOCKET
        echo "radio: not running (no socket at $SOCKET)" >&2
        exit 1
    end
end

function ipc
    printf '%s\n' $argv | $SOCAT - $SOCKET 2>/dev/null
end

function jsonEscape
    printf '%s' $argv | $JQ -Rs .
end

# query PROPERTY -> prints the property value, empty on failure
function query
    set -l resp (ipc (printf '{"command":["get_property","%s"]}' $argv[1]))
    if test (count $resp) -eq 0; or not string match -q '*"error":"success"*' -- $resp[1]
        return 1
    end
    printf '%s\n' $resp[1] | $JQ -r '.data | if . == null then "" else tostring end'
end

function stations
    $CURL -s "http://localhost:$PORT/favorites" | $JQ -r '.[].name'
end

function resolveStation
    set -l url (
        $CURL -s "http://localhost:$PORT/favorites" |
        $JQ -r --arg name "$argv[1]" '.[] | select(.name == $name) | .url'
    )
    if test (count $url) -eq 0
        return 1
    end
    echo $url[1]
end

function showStatus
    requireSocket

    set -l label audible
    set -l mute (query mute)
    if test "$mute" = true
        set label muted
    end

    set -l station (query user-data/bbrf/name)
    if test -z "$station"
        set station $DEFAULT_STATION
    end

    echo "radio: $label - $station"

    set -l title (query media-title)
    if test -n "$title"
        echo "  $title"
    end
end

function switchStation
    requireSocket

    set -l name $argv[1]
    set -l url (resolveStation $name)
    or begin
        echo "radio: unknown station '$name' (see: radio stations)" >&2
        exit 1
    end

    set -l resp (ipc (printf '{"command":["loadfile",%s]}' (jsonEscape $url)))
    if not test (count $resp) -gt 0; or not string match -q '*"error":"success"*' -- $resp[1]
        echo "radio: mpv failed to load $url" >&2
        exit 1
    end

    # remember the station so `radio status` (and future tools) can show it
    ipc (printf '{"command":["set_property","user-data/bbrf/name",%s]}' (jsonEscape $name)) > /dev/null
    echo "radio: now playing $name"
end

if test (count $argv) -eq 0
    showStatus
    exit 0
end

switch $argv[1]
    case on
        requireSocket
        ipc '{"command":["set_property","mute",false]}' > /dev/null
        echo "radio: audible"
    case off
        requireSocket
        ipc '{"command":["set_property","mute",true]}' > /dev/null
        echo "radio: muted"
    case toggle
        requireSocket
        set -l mute (query mute)
        if test "$mute" = true
            ipc '{"command":["set_property","mute",false]}' > /dev/null
            echo "radio: audible"
        else
            ipc '{"command":["set_property","mute",true]}' > /dev/null
            echo "radio: muted"
        end
    case station
        if test (count $argv) -lt 2
            echo "usage: radio station NAME" >&2
            exit 1
        end
        switchStation $argv[2]
    case pick
        requireSocket
        if not type -q rofi
            echo "radio: rofi not found in PATH" >&2
            exit 1
        end
        set -l choice (stations | $SORT -u | rofi -dmenu -i -matching fuzzy -p "Radio")
        if test (count $choice) -eq 0
            exit 0
        end
        switchStation $choice[1]
    case stations
        stations
    case status
        showStatus
    case '*'
        echo "usage: radio [on|off|toggle|status|stations|station NAME|pick]" >&2
        exit 1
end
