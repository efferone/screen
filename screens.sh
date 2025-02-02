#!/bin/bash

# wake second screen after sleep and practice logging

# Logging function
log_message() {
    logger -t "screens" "$1"
    echo "$1"
}

# is xrandar installed, it really should be. leaving this is here but going to comment it out 
check_xrandr() {
    if ! command -v xrandr >/dev/null 2>&1; then
        log_message "xrandr not found. install xrandr package asap."
        exit 1
    fi
}

# get monitors
get_displays() {
    # set them
    MONITOR="HDMI-1"
    TV="HDMI-2"
    
    log_message "Got monitor=$MONITOR"
    log_message "Got TV=$TV"
}

# get default resolution for second display
get_tv_mode() {
    TV_MODE=$(xrandr | grep -A 1 "^$TV connected" | grep -v "connected" | grep "+" | head -n 1 | awk '{print $1}')
    
    if [ -z "$TV_MODE" ]; then
        TV_MODE="3840x2160"
        log_message "No default mode found, using fallback: $TV_MODE"
    else
        log_message "Found default mode: $TV_MODE"
    fi
}

# reset second monitor/tv
reset_secondary() {
    get_displays
    get_tv_mode
    
    log_message "Resetting ($TV)"
    
    # off
    xrandr --output "$TV" --off
    sleep 2
    
    # and on again. change right-of and rate if needed etc.
    xrandr --output "$TV" --mode "$TV_MODE" --right-of "$MONITOR" --rate 60
    
    log_message "TV reset completed with mode: $TV_MODE"
}

# run it
check_xrandr
reset_secondary