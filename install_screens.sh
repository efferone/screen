#!/bin/bash

# script to install monitor reset service

# Check for root/sudo permissions
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo" 
   exit 1
fi

# get the current user
CURRENT_USER=$(logname)

# Paths
SCRIPT_NAME="screens.sh"
SCRIPT_DEST="/usr/local/bin/${SCRIPT_NAME}"

# paths for different inits
SYSTEMD_SERVICE_NAME="screen.service"
SYSTEMD_SERVICE_DEST="/etc/systemd/system/${SYSTEMD_SERVICE_NAME}"
OPENRC_SERVICE_NAME="screen"
OPENRC_SERVICE_DEST="/etc/init.d/${OPENRC_SERVICE_NAME}"
RUNIT_SERVICE_DIR="/etc/sv/screen"
SYSV_SERVICE_NAME="screen-reset"
SYSV_SERVICE_DEST="/etc/init.d/${SYSV_SERVICE_NAME}"

# adding some logging/output
log_message() {
    echo "[MONITOR RESET INSTALL] $1"
}

# detect init system
detect_init_system() {
    if [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif [[ -d /etc/init.d && -f /sbin/openrc ]]; then
        echo "openrc"
    elif [[ -d /etc/sv && -f /etc/runit/1 ]]; then
        echo "runit"
    elif [[ -d /etc/init.d && -f /sbin/init && ! -f /sbin/openrc ]]; then
        echo "sysv"
    else
        echo "unknown"
    fi
}

# install script has to be run in the dir containing the other script
script_check() {
    if [[ ! -f "$SCRIPT_NAME" ]]; then
        log_message "reset script (${SCRIPT_NAME}) not found in current directory."
        exit 1
    fi
}

# install the script
install_script() {
    install -m 755 "$SCRIPT_NAME" "$SCRIPT_DEST"
    log_message "Installed monitor reset script to ${SCRIPT_DEST}"
}

# systemd service install
install_systemd() {
    sed "s/USER/${CURRENT_USER}/g" screen.service.template > "$SYSTEMD_SERVICE_DEST"
    log_message "Created systemd service at ${SYSTEMD_SERVICE_DEST}"
    
    systemctl daemon-reload
    systemctl enable "${SYSTEMD_SERVICE_NAME}"
    systemctl start "${SYSTEMD_SERVICE_NAME}"
    log_message "Enabled and started systemd service"
}

# OpenRC service install
install_openrc() {
    cat > "$OPENRC_SERVICE_DEST" << EOF
#!/sbin/openrc-run

name="Monitor Reset Service"
description="Reset monitors after system resume"
command="/usr/local/bin/screens.sh"
command_user="${CURRENT_USER}"
depend() {
    need localmount
    after resume
}

start_pre() {
    export DISPLAY=:0
    export XAUTHORITY="/home/${CURRENT_USER}/.Xauthority"
}
EOF
    
    chmod 755 "$OPENRC_SERVICE_DEST"
    rc-update add "$OPENRC_SERVICE_NAME" default
    rc-service "$OPENRC_SERVICE_NAME" start
    log_message "Created and started OpenRC service"
}

# Runit service install
install_runit() {
    mkdir -p "${RUNIT_SERVICE_DIR}"
    
    # run script
    cat > "${RUNIT_SERVICE_DIR}/run" << EOF
#!/bin/sh
exec 2>&1
export DISPLAY=:0
export XAUTHORITY="/home/${CURRENT_USER}/.Xauthority"
exec chpst -u ${CURRENT_USER} /usr/local/bin/screens.sh
EOF
    
    chmod 755 "${RUNIT_SERVICE_DIR}/run"
    
    # finish script
    cat > "${RUNIT_SERVICE_DIR}/finish" << EOF
#!/bin/sh
exit 0
EOF
    
    chmod 755 "${RUNIT_SERVICE_DIR}/finish"
    
    # enable service
    ln -s "${RUNIT_SERVICE_DIR}" /etc/service/
    log_message "Created and enabled runit service"
}

# SysV init service install, genAI helped with this
install_sysv() {
    # create service script
    cat > "$SYSV_SERVICE_DEST" << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          screen-reset
# Required-Start:    \$remote_fs \$syslog
# Required-Stop:     \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Monitor reset service
# Description:       Service to reset monitors after system resume
### END INIT INFO

SCRIPT="/usr/local/bin/screens.sh"
RUNAS="${CURRENT_USER}"

start() {
    echo 'Service is event-based, no continuous process needed.' >&2
    return 0
}

stop() {
    echo 'Service is event-based, no continuous process needed.' >&2
    return 0
}

status() {
    echo 'Service is event-based. Check /var/log/syslog for activation events.' >&2
    return 0
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    status)
        status
        ;;
    trigger)
        # This is called by the PM hook
        export DISPLAY=:0
        export XAUTHORITY="/home/\$RUNAS/.Xauthority"
        su -c "\$SCRIPT" \$RUNAS
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|trigger}"
        exit 1
        ;;
esac

exit 0
EOF

    chmod 755 "$SYSV_SERVICE_DEST"
    
    # create trigger in pm-utils
    mkdir -p /etc/pm/sleep.d
    cat > "/etc/pm/sleep.d/99screen-reset" << EOF
#!/bin/sh
case "\$1" in
    resume|thaw)
        sleep 2  # Give X server time to reconnect
        /etc/init.d/screen-reset trigger
        ;;
esac
EOF
    chmod 755 "/etc/pm/sleep.d/99screen-reset"

    # also need to create an acpi event handler for laptops
    mkdir -p /etc/acpi/events
    cat > "/etc/acpi/events/screen-reset" << EOF
event=button/lid.*
action=/etc/init.d/screen-reset trigger
EOF
    
    # enable service (though it's really just for the init script to be in place)
    update-rc.d screen-reset defaults
    log_message "Created SysV init service and PM hooks"
}

# main install process
main() {
    script_check
    install_script
    
    INIT_SYSTEM=$(detect_init_system)
    log_message "Detected init system: ${INIT_SYSTEM}"
    
    case "$INIT_SYSTEM" in
        systemd)
            install_systemd
            ;;
        openrc)
            install_openrc
            ;;
        runit)
            install_runit
            ;;
        sysv)
            install_sysv
            ;;
        *)
            log_message "Unsupported init system. Please leave feedback and I'll work on the script"
            exit 1
            ;;
    esac
    
    log_message "Installation completed successfully!"
}

# Run the installation
main
