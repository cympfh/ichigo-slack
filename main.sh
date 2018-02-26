#!/bin/bash

MENU_URL=http://menu.2ch.net/bbsmenu.html
BDNAME="ニュー速VIP"
THNAME="苺ましまろ"

# get board url of VIP
get-board() {
    curl -s "$MENU_URL" | nkf |
    grep ">${BDNAME}<" |
    grep -o "http[^>]*"
}

# get thread url of Ichigo
get-thread() {
    BD_URL=$(get-board)
    DOM=$(echo "$BD_URL" | cut -d '/' -f 3) ## *.2ch.net
    BID=$(echo "$BD_URL" | cut -d '/' -f 4) ## news4vip
    SUBJECT_URL="${BD_URL}subject.txt"
    TID=$(curl -s "$SUBJECT_URL" | nkf | grep "<>${THNAME} " | cut -d'<' -f1 | cut -d '.' -f1)
    echo "http://${DOM}/test/read.cgi/${BID}/${TID}"
}

html-trim() {
    sed 's,<div>,,g; s,</div>,,g; s,<span>,,g; s,</span>,,g' |
    sed 's/<a href[^>]*>//g; s,</a>,,g'
}

html-unescape() {
    sed 's/&gt;/>/g; s/&lt;/</g; s/&quot;/"/g'
}

get-body() {
    curl -sL "$(get-thread)" | nkf |
    sed 's/<div class="post"/\n&/g' | grep '^<div class="post"' | sed 's/<div class="push".*//g' |
    sed 's;<div class="post" id="\([0-9]*\)" data-date="[0-9]*" data-userid="ID:\([^"]*\)" data-id="[0-9]*"><div class="meta"><span class="number">[0-9]*</span><span class="name"><b>.*</b></span><span class="date">[^<]*</span><span class="uid">ID:[^<]*</span></div><div class="message"><span class="escaped"> \(.*\)$;{"number": \1, "id": "\2", "text": "\3"};g' |
    html-trim > /tmp/ichigo.body
    cat /tmp/ichigo.body | wc -l > /tmp/ichigo.lines
}

source ./config.sh

LAST_LINES=0
[ -f /tmp/ichigo.lines ] && LAST_LINES=$(cat /tmp/ichigo.lines)

while :; do

    get-body
    tail -n +$((LAST_LINES + 1)) /tmp/ichigo.body |
    while read line; do
        echo "$line" >/tmp/ichigo.line
        cat <<EOM >/tmp/ichigo.slack.payload
{
    "channel": "#ichigo",
    "icon_emoji": ":strawberry:",
    "username": "$(jq -r .id /tmp/ichigo.line)",
    "text": "$(jq -r .text /tmp/ichigo.line | sed 's/<br>/\n/g')"
}
EOM
        cat /tmp/ichigo.slack.payload
        curl -X POST --data @/tmp/ichigo.slack.payload "$SLACK_WEB_HOOK"
    done

    sleep 30
done
