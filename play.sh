#!/bin/zsh
AUDIO_FILE="$(dirname $(realpath $0))/Ballaké.m4a"
# trap play_sigint SIGINT
# trap play_exit EXIT

play_exit() {
    if [ -n "$AUDIO_PID" ]; then
        kill "$AUDIO_PID" 2>/dev/null
        wait "$AUDIO_PID" 2>/dev/null
        unset AUDIO_PID
        exit
    fi
}

play_sigint() {
    if [ -n "$AUDIO_PID" ]; then
        kill "$AUDIO_PID" 2>/dev/null
        wait "$AUDIO_PID" 2>/dev/null
        unset AUDIO_PID
        logE "User terminated the script. Cleaning up and exiting..."
        exit 1
    fi
}

play() {
    # Play the audio file using afplay (default audio player in macOS)
    if [ -f "$AUDIO_FILE" ]; then
        afplay "$AUDIO_FILE" &
        AUDIO_PID=$!
    fi
}