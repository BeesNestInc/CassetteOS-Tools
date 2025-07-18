#!/bin/bash
#
#           CassetteOS Uninstaller Script v0.0.6#
#   GitHub: https://github.com/BeesNestInc/CassetteOS
#   Requires: bash, mv, rm, tr, grep, sed
#
#   This script will remove CasaOS from your system.
#
#   This only work on  Linux systems. Please
#   open an issue if you notice any bugs.
#
set -e
clear

# shellcheck disable=SC2016
echo '
 ██████╗ █████╗ ███████╗███████╗███████╗████████╗████████╗███████╗ ██████╗ ███████╗
██╔════╝██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝██╔═══██╗██╔════╝
██║     ███████║███████╗███████╗█████╗     ██║      ██║   █████╗  ██║   ██║███████╗
██║     ██╔══██║╚════██║╚════██║██╔══╝     ██║      ██║   ██╔══╝  ██║   ██║╚════██║
╚██████╗██║  ██║███████║███████║███████╗   ██║      ██║   ███████╗╚██████╔╝███████║
 ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝ ╚═════╝ ╚══════╝
'

###############################################################################
# Golbals                                                                     #
###############################################################################

# Not every platform has or needs sudo (https://termux.com/linux.html)
((EUID)) && sudo_cmd="sudo"

readonly CASA_SERVICES=(
    "cassetteos-gateway.service"
"cassetteos-message-bus.service"
"cassetteos-user-service.service"
"cassetteos-local-storage.service"
"cassetteos-app-management.service"
"cassetteos.service"  # must be the last one so update from UI can work 
    "devmon@devmon.service"
)

readonly CASA_EXEC=cassetteos
readonly CASA_BIN=/usr/local/bin/cassetteos
readonly CASA_SERVICE_USR=/usr/lib/systemd/system/cassetteos.service
readonly CASA_SERVICE_LIB=/lib/systemd/system/cassetteos.service
readonly CASA_SERVICE_ETC=/etc/systemd/system/cassetteos.service
readonly CASA_ADDON1=/etc/udev/rules.d/11-usb-mount.rules
readonly CASA_ADDON2=/etc/systemd/system/usb-mount@.service
readonly CASA_UNINSTALL_PATH=/usr/bin/cassetteos-uninstall

# New Casa Files
readonly MANIFEST=/var/lib/cassetteos/manifest
readonly CASA_CONF_PATH_OLD=/etc/cassetteos.conf
readonly CASA_CONF_PATH=/etc/cassetteos
readonly CASA_RUN_PATH=/var/run/cassetteos
readonly CASA_USER_FILES=/var/lib/cassetteos
readonly CASA_LOGS_PATH=/var/log/cassetteos
readonly CASA_HELPER_PATH=/usr/share/cassetteos

readonly COLOUR_RESET='\e[0m'
readonly aCOLOUR=(
    '\e[38;5;154m' # green  	| Lines, bullets and separators
    '\e[1m'        # Bold white	| Main descriptions
    '\e[90m'       # Grey		| Credits
    '\e[91m'       # Red		| Update notifications Alert
    '\e[33m'       # Yellow		| Emphasis
)

UNINSTALL_ALL_CONTAINER=false
REMOVE_IMAGES="none"
REMOVE_APP_DATA=false

###############################################################################
# Helpers                                                                     #
###############################################################################

#######################################
# Custom printing function
# Globals:
#   None
# Arguments:
#   $1 0:OK   1:FAILED  2:INFO  3:NOTICE
#   message
# Returns:
#   None
#######################################

Show() {
    # OK
    if (($1 == 0)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]}  OK  $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # FAILED
    elif (($1 == 1)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[3]}FAILED$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # INFO
    elif (($1 == 2)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[0]} INFO $COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    # NOTICE
    elif (($1 == 3)); then
        echo -e "${aCOLOUR[2]}[$COLOUR_RESET${aCOLOUR[4]}NOTICE$COLOUR_RESET${aCOLOUR[2]}]$COLOUR_RESET $2"
    fi
}

Warn() {
    echo -e "${aCOLOUR[3]}$1$COLOUR_RESET"
}

trap 'onCtrlC' INT
onCtrlC() {
    echo -e "${COLOUR_RESET}"
    exit 1
}

Detecting_CasaOS() {
    if [[ ! -x "$(command -v ${CASA_EXEC})" ]]; then
        Show 2 "CasaOS is not detected, exit the script."
        exit 1
    else
        Show 0 "This script will delete the containers you no longer use, and the CasaOS configuration files."
    fi
}

Unistall_Container() {
    if [[ ${UNINSTALL_ALL_CONTAINER} == true && "$(${sudo_cmd} docker ps -aq)" != "" ]]; then
        Show 2 "Start deleting containers."
        ${sudo_cmd} docker stop "$(${sudo_cmd} docker ps -aq)" || Show 1 "Failed to stop containers."
        ${sudo_cmd} docker rm "$(${sudo_cmd} docker ps -aq)" || Show 1 "Failed to delete all containers."
    fi
}

Remove_Images() {
    if [[ ${REMOVE_IMAGES} == "all" && "$(${sudo_cmd} docker images -q)" != "" ]]; then
        Show 2 "Start deleting all images."
        ${sudo_cmd} docker rmi "$(${sudo_cmd} docker images -q)" || Show 1 "Failed to delete all images."
    elif [[ ${REMOVE_IMAGES} == "unuse" && "$(${sudo_cmd} docker images -q)" != "" ]]; then
        Show 2 "Start deleting unuse images."
        ${sudo_cmd} docker image prune -af || Show 1 "Failed to delete unuse images."
    fi
}

Uninstall_Casaos() {

    for SERVICE in "${CASA_SERVICES[@]}"; do
        Show 2 "Stopping ${SERVICE}..."
        systemctl stop "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."
        systemctl disable "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."
    done

    # Remove Service file
    if [[ -f ${CASA_SERVICE_USR} ]]; then
        ${sudo_cmd} rm -rf ${CASA_SERVICE_USR}
    fi

    if [[ -f ${CASA_SERVICE_LIB} ]]; then
        ${sudo_cmd} rm -rf ${CASA_SERVICE_LIB}
    fi

    if [[ -f ${CASA_SERVICE_ETC} ]]; then
        ${sudo_cmd} rm -rf ${CASA_SERVICE_ETC}
    fi

    if [[ -f ${CASA_ADDON1} ]]; then
        ${sudo_cmd} rm -rf ${CASA_ADDON1}
    fi

    if [[ -f ${CASA_ADDON2} ]]; then
        ${sudo_cmd} rm -rf ${CASA_ADDON2}
    fi

    if [[ -f ${CASA_BIN} ]]; then
        ${sudo_cmd} rm -rf ${CASA_BIN} || Show 1 "Failed to delete CasaOS exec file."
    fi

    # New Casa Files

    if [[ -f ${CASA_CONF_PATH_OLD} ]]; then
        ${sudo_cmd} rm -rf ${CASA_CONF_PATH_OLD}
    fi

    if [[ -f ${MANIFEST} ]]; then
        ${sudo_cmd} cat ${MANIFEST} | while read -r line; do
            if [[ -f ${line} ]]; then
                ${sudo_cmd} rm -rf "${line}"
            fi
        done
    fi

    if [[ -d ${CASA_USER_FILES} ]]; then
        ${sudo_cmd} rm -rf ${CASA_USER_FILES}/[0-9]*
        ${sudo_cmd} rm -rf ${CASA_USER_FILES}/db
        ${sudo_cmd} rm -rf ${CASA_USER_FILES}/*.db
    fi

    ${sudo_cmd} rm -rf ${CASA_USER_FILES}/www
    ${sudo_cmd} rm -rf ${CASA_USER_FILES}/migration

    if [[ -d ${CASA_HELPER_PATH} ]]; then
        ${sudo_cmd} rm -rf ${CASA_HELPER_PATH}
    fi

    if [[ -d ${CASA_LOGS_PATH} ]]; then
        ${sudo_cmd} rm -rf ${CASA_LOGS_PATH}
    fi

    if [[ ${REMOVE_APP_DATA} = true ]]; then
        $sudo_cmd rm -fr /DATA/AppData || Show 1 "Failed to delete AppData."
    fi

    if [[ -d ${CASA_CONF_PATH} ]]; then
        ${sudo_cmd} rm -rf ${CASA_CONF_PATH}
    fi

    if [[ -d ${CASA_RUN_PATH} ]]; then
        ${sudo_cmd} rm -rf ${CASA_RUN_PATH}
    fi

    if [[ -f ${CASA_UNINSTALL_PATH} ]]; then
        ${sudo_cmd} rm -rf ${CASA_UNINSTALL_PATH}
    fi

}

# Check user
if [ "$(id -u)" -ne 0 ];then
    Show 1 "Please execute with a root user, or use ${aCOLOUR[4]}sudo casaos-uninstall${COLOUR_RESET}."
    exit 1
fi


#Inputs

Detecting_CasaOS

while true; do
    echo -n -e "         ${aCOLOUR[4]}Do you want delete all containers? Y/n :${COLOUR_RESET}"
    read -r input
    case $input in
    [yY][eE][sS] | [yY])
        UNINSTALL_ALL_CONTAINER=true
        break
        ;;
    [nN][oO] | [nN])
        UNINSTALL_ALL_CONTAINER=false
        break
        ;;
    *)
        Warn "         Invalid input..."
        ;;
    esac
done < /dev/tty

if [[ ${UNINSTALL_ALL_CONTAINER} == true ]]; then
    while true; do
        echo -n -e "         ${aCOLOUR[4]}Do you want delete all images? Y/n :${COLOUR_RESET}"
        read -r input
        case $input in
        [yY][eE][sS] | [yY])
            REMOVE_IMAGES="all"
            break
            ;;
        [nN][oO] | [nN])
            REMOVE_IMAGES="none"
            break
            ;;
        *)
            Warn "         Invalid input..."
            ;;
        esac
    done < /dev/tty

    while true; do
        echo -n -e "         ${aCOLOUR[4]}Do you want delete all AppData of CasaOS? Y/n :${COLOUR_RESET}"
        read -r input
        case $input in
        [yY][eE][sS] | [yY])
            REMOVE_APP_DATA=true
            break
            ;;
        [nN][oO] | [nN])
            REMOVE_APP_DATA=false
            break
            ;;
        *)
            Warn "         Invalid input..."
            ;;
        esac
    done < /dev/tty
else
    while true; do
        echo -n -e "         ${aCOLOUR[4]}Do you want to delete all images that are not used by the container? Y/n :${COLOUR_RESET}"
        read -r input
        case $input in
        [yY][eE][sS] | [yY])
            REMOVE_IMAGES="unuse"
            break
            ;;
        [nN][oO] | [nN])
            REMOVE_IMAGES="none"
            break
            ;;
        *)
            Warn "         Invalid input..."
            ;;
        esac
    done < /dev/tty
fi


Unistall_Container
Remove_Images
Uninstall_Casaos