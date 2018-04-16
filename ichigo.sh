#!/bin/bash

MENU_URL=http://menu.2ch.net/bbsmenu.html
BDNAME="ニュー速VIP"
THNAME="苺ましまろ"
SESSION_FILE=/tmp/ichigo.session

if [ ! -f ./config.sh ]; then
    echo "Not found config.sh"
    exit 1
fi
source ./config.sh

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
    TID=$(curl -s "$SUBJECT_URL" | nkf | grep "<>${THNAME} " | cut -d'<' -f1 | cut -d '.' -f1 | head -1)
    echo "http://${DOM}/test/read.cgi/${BID}/${TID}"
}

# get content and helpers
html-trim() {
    sed 's,<div>,,g; s,</div>,,g; s,<span>,,g; s,</span>,,g' |
    sed 's/<a[^>]*>//g; s,</a>,,g' |
    sed 's/>>/:point_right:/g'
}

html-unescape() {
    sed 's/&gt;/>/g; s/&lt;/</g; s/&quot;/"/g'
}

get-body() {
    curl -sL "$1" | nkf |
        sed 's/<div class="post"/\n&/g' | grep '^<div class="post"' | sed 's/<div class="push".*//g' |
        sed 's,<div class="post" id="\([0-9]*\)" data-date="[0-9]*" data-userid="ID:\([^"]*\)" data-id="[0-9]*"><div class="meta"><span class="number">[0-9]*</span><span class="name"><b>.*</b></span><span class="date">\([^<]*\)</span><span class="uid">ID:[^<]*</span></div><div class="message"><span class="escaped">,\2\t,g' |
        sed 's/ *<br> *$//g' |
        html-trim | html-unescape
}

# icons for slack
NUM_ICONS=$(wc -l < icons.txt)
get-icon() {
    LINE_ICON=$(( 0x$(echo $1 | md5sum | tr -dc '[0-9a-f]' | head -c 4) % NUM_ICONS + 1 ))
    head -n $LINE_ICON icons.txt | tail -n 1
}

# Slack post
slack-post-info() {
    cat <<EOM >/tmp/ichigo.slack.payload
{
    "channel": "#ichigo",
    "icon_emoji": ":information_source:",
    "username": "info",
    "text": "$1"
}
EOM
    curl -X POST --data @/tmp/ichigo.slack.payload "$SLACK_WEB_HOOK"
}

slack-post() {
    ICON="$1"  # url
    ID="$2"
    TEXT="$3"
    cat <<EOM >/tmp/ichigo.slack.payload
{
    "channel": "#ichigo",
    "icon_url": "${ICON}",
    "username": "${ID}",
    "text": "$(echo ${TEXT} | sed 's/ *<br> */\\n/g')"
}
EOM
    cat /tmp/ichigo.slack.payload
    curl -X POST --data @/tmp/ichigo.slack.payload "$SLACK_WEB_HOOK"
}

slack-post-info "Last Session: $(cat "$SESSION_FILE" | tr '\n' : | sed 's/:$//g')"

while :; do

    # last session
    LAST_TH_URL=$(head -1 "$SESSION_FILE")
    LAST_LINES=$(tail -1 "$SESSION_FILE")

    # get new session
    TH_URL=$(get-thread)
    if [ "$LAST_TH_URL" != "$TH_URL" ]; then
        echo "Thread Moved: $TH_URL"
        slack-post-info "Thread Moved: $TH_URL"
        LAST_LINES=0
    fi

    # get content
    get-body "${TH_URL}" > /tmp/ichigo.body

    # post news
    tail -n +$((LAST_LINES + 1)) /tmp/ichigo.body |
    while read line; do
        ID=${line%	*}
        TEXT=${line#*	}
        ICON=$(get-icon "$ID")
        slack-post "$ICON" "$ID" "$TEXT"
    done

    # save new session
    LAST_TH_URL=${TH_URL}
    LAST_LINES=$(wc -l /tmp/ichigo.body | awk '{print $1}')
    echo "$LAST_TH_URL:$LAST_LINES"
    cat <<EOM >"$SESSION_FILE"
${LAST_TH_URL}
${LAST_LINES}
EOM

    sleep 30
done
