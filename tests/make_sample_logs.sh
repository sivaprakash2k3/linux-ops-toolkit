#!/usr/bin/env bash
# make_sample_logs.sh DIR - create fake nginx and SSH logs for testing log_report.sh

set -eu

dir=${1:?Usage: $0 DIR}
mkdir -p "$dir"
access="$dir/access.log"
auth="$dir/auth.log"
: > "$access"
: > "$auth"

web_line() {  # ip path status
    printf '%s - - [22/Oct/2026:10:%02d:%02d +0530] "GET %s HTTP/1.1" %s 512 "-" "Mozilla/5.0"\n' \
        "$1" $((RANDOM % 60)) $((RANDOM % 60)) "$2" "$3" >> "$access"
}

auth_line() {  # message
    printf '2026-10-22T10:%02d:%02d.000000+05:30 vmhost sshd[%d]: %s\n' \
        $((RANDOM % 60)) $((RANDOM % 60)) $((1000 + RANDOM % 8000)) "$1" >> "$auth"
}

for _ in $(seq 1 40); do web_line 203.0.113.10 / 200; done
for _ in $(seq 1 25); do web_line 203.0.113.11 /about.html 200; done
for _ in $(seq 1 15); do web_line 203.0.113.12 /contact.html 200; done
for i in $(seq 1 12); do web_line 198.51.100.7 "/missing-$i" 404; done
for p in /.env /wp-login.php /phpmyadmin/ /.git/config; do web_line 198.51.100.7 "$p" 404; done
for _ in 1 2 3; do web_line 203.0.113.10 /api/data 500; done

for _ in $(seq 1 30); do auth_line "Failed password for invalid user admin from 198.51.100.7 port 41000 ssh2"; done
for _ in $(seq 1 12); do auth_line "Failed password for root from 198.51.100.7 port 41001 ssh2"; done
for _ in $(seq 1 6); do auth_line "Failed password for invalid user test from 192.0.2.44 port 42000 ssh2"; done
auth_line "Accepted publickey for sivaprakash from 192.168.1.20 port 50000 ssh2: ED25519 SHA256:example"
auth_line "Accepted password for sivaprakash from 192.168.1.20 port 50001 ssh2"

echo "Sample logs written to $dir"
