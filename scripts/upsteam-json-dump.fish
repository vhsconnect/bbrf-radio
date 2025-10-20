#! /usr/bin/env fish

set base_url 'https://de2.api.radio-browser.info/json/stations'
set i 0
set limit 10000
set output_file 'allstations.json'

echo '' >$output_file

while true
    set offset (math $limit \* $i)
    if test $i -gt 7
        exit 1
    end
    set url "$base_url?offset=$offset&limit=$limit"

    echo "Fetching stations with offset $offset"
    echo $url

    curl -s "$url" >>$output_file

    set i (math $i + 1)

    echo "Waiting before next request .-."
    sleep 6
end

echo "Done ._."
