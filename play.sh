#!/bin/zsh

cleanup_exit() {
    if [ -n "$AUDIO_PID" ]; then
        kill "$AUDIO_PID" 2>/dev/null
        wait "$AUDIO_PID" 2>/dev/null
        exit 1
    fi
}

cleanup_signint() {
    if [ -n "$AUDIO_PID" ]; then
        kill "$AUDIO_PID" 2>/dev/null
        wait "$AUDIO_PID" 2>/dev/null
        echo "      User terminated the script. Cleaning up and exiting..."
        exit 1
    fi
}


# Trap the script termination signals
trap cleanup_signint SIGINT
trap cleanup_exit EXIT

# Play the audio file using afplay (default audio player in macOS)
AUDIO_FILE="./Two_Swords.m4a"

if [ -f "$AUDIO_FILE" ]; then
    while true; do
        afplay "$AUDIO_FILE" &
        AUDIO_PID=$!
        wait "$AUDIO_PID"
    done
fi