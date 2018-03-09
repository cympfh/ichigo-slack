#!/bin/bash

MENU_URL=http://2ch.sc/bbsmenu.html
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
    sed 's/<a[^>]*>//g; s,</a>,,g'
}

html-unescape() {
    sed 's/&gt;/>/g; s/&lt;/</g; s/&quot;/"/g'
}

get-body() {
    curl -sL "$1" | nkf |
        grep '^<dt>' |
        sed 's/^.* ID:\(.*\).net<dd> \(.*\) <br><br>$/\1\t\2/g' |
        html-trim | html-unescape
}

source ./config.sh

LAST_THREAD=
[ -f /tmp/ichigo.thread ] && LAST_THREAD=$(cat /tmp/ichigo.thread)
LAST_LINES=0
[ -f /tmp/ichigo.lines ] && LAST_LINES=$(cat /tmp/ichigo.lines)
echo "Last Session: ${LAST_THREAD} ${LAST_LINES}"

while :; do

    # previous thread & lines
    TH_URL=$(get-thread)
    if [ $LAST_THREAD != $TH_URL ]; then
        echo "Thread Moved: $TH_URL"
        LAST_LINES=0
    else
        LAST_LINES=$(cat /tmp/ichigo.lines)
    fi

    # get content
    get-body "${TH_URL}" > /tmp/ichigo.body
    echo "${TH_URL}" > /tmp/ichigo.thread
    cat /tmp/ichigo.body | wc -l > /tmp/ichigo.lines
    echo "Body: $(cat /tmp/ichigo.lines) lines"

    # new
    tail -n +$((LAST_LINES + 1)) /tmp/ichigo.body |
    while read line; do
        ID=${line%	*}
        TEXT=${line#*	}
        cat <<EOM >/tmp/ichigo.slack.payload
{
    "channel": "#ichigo",
    "icon_emoji": ":strawberry:",
    "username": "${ID}",
    "text": "$(echo ${TEXT} | sed 's/<br>/\\n/g')"
}
EOM
        cat /tmp/ichigo.slack.payload
        curl -X POST --data @/tmp/ichigo.slack.payload "$SLACK_WEB_HOOK"
    done

    sleep 30
done
