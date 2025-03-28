#!/bin/zsh
cleanup() { if [ -n "$AUDIO_PID" ]; then kill "$AUDIO_PID" 2>/dev/null; wait "$AUDIO_PID" 2>/dev/null; fi }
# Trap the script termination signals
trap cleanup SIGINT
trap cleanup EXIT
# Play the audio file using afplay (default audio player in macOS)
AUDIO_FILE="./Two_Swords.m4a"
if [ -f "$AUDIO_FILE" ]; then afplay "$AUDIO_FILE" & ; AUDIO_PID=$! ; fi