#!/usr/bin/bash
#
#           CassetteOS Installer Script v0.0.9
#   GitHub: https://github.com/BeesNestInc/CassetteOS
#   Requires: bash, mv, rm, tr, grep, sed, curl/wget, tar, smartmontools, parted, ntfs-3g, net-tools
#
#   This script installs CassetteOS to your system.
#   Usage:
#
#       $ wget -qO- https://github.com/BeesNestInc/CassetteOS-Tools/releases/download/v0.0.9/install.sh | sudo bash
#         or
#       $ curl -fsSL https://github.com/BeesNestInc/CassetteOS-Tools/releases/download/v0.0.9/install.sh | sudo bash
#
#   In automated environments, you may want to run as root.
#   If using curl, we recommend using the -fsSL flags.
#
#   This only work on  Linux systems. Please
#   open an issue if you notice any bugs.
#
clear
echo -e "\e[0m\c"

# shellcheck disable=SC2016
echo '
 ██████╗ █████╗ ███████╗███████╗███████╗████████╗████████╗███████╗ ██████╗ ███████╗
██╔════╝██╔══██╗██╔════╝██╔════╝██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝██╔═══██╗██╔════╝
██║     ███████║███████╗███████╗█████╗     ██║      ██║   █████╗  ██║   ██║███████╗
██║     ██╔══██║╚════██║╚════██║██╔══╝     ██║      ██║   ██╔══╝  ██║   ██║╚════██║
╚██████╗██║  ██║███████║███████║███████╗   ██║      ██║   ███████╗╚██████╔╝███████║
 ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝   ╚═╝      ╚═╝   ╚══════╝ ╚═════╝ ╚══════╝
'
export PATH=/usr/sbin:$PATH
export DEBIAN_FRONTEND=noninteractive
set -e

###############################################################################
# GOLBALS                                                                     #
###############################################################################

# version
readonly CASSETTEOS_VERSION="v0.0.9"
((EUID)) && sudo_cmd="sudo"

# shellcheck source=/dev/null
source /etc/os-release

# SYSTEM REQUIREMENTS
readonly MINIMUM_DISK_SIZE_GB="5"
readonly MINIMUM_MEMORY="400"
readonly MINIMUM_DOCKER_VERSION="20"
# 🛠️ 本体インストール用
readonly CASSETTE_DEPENDS_LIST=(
  "wget:wget"
  "curl:curl"
  "smartctl:smartmontools"
  "parted:parted"
  "ntfs-3g:ntfs-3g"
  "netstat:net-tools"
  "udevil:udevil"
  "smbd:samba"
  "mount.cifs:cifs-utils"
  "mount.mergerfs:mergerfs"
  "unzip:unzip"
)

# 📡 WiFiセットアップ用
readonly WIFI_SETUP_DEPENDS_LIST=(
  "avahi-daemon:avahi-daemon"
  "hostapd:hostapd"
  "dnsmasq:dnsmasq"
  "iw":"iw"
)

# 🗃️ ホストDB用
readonly HOST_DB_DEPENDS_LIST=(
  "psql:postgresql"
)

# SYSTEM INFO
PHYSICAL_MEMORY=$(LC_ALL=C free -m | awk '/Mem:/ { print $2 }')
readonly PHYSICAL_MEMORY

FREE_DISK_BYTES=$(LC_ALL=C df -P / | tail -n 1 | awk '{print $4}')
readonly FREE_DISK_BYTES

readonly FREE_DISK_GB=$((FREE_DISK_BYTES / 1024 / 1024))

LSB_DIST=$( ([ -n "${ID_LIKE}" ] && echo "${ID_LIKE}") || ([ -n "${ID}" ] && echo "${ID}"))
readonly LSB_DIST

DIST=$(echo "${ID}")
readonly DIST

UNAME_M="$(uname -m)"
readonly UNAME_M

UNAME_U="$(uname -s)"
readonly UNAME_U

readonly CASSETTE_CONF_PATH=/etc/cassetteos/gateway.ini
readonly CASSETTE_UNINSTALL_URL="https://github.com/BeesNestInc/CassetteOS-Tools/releases/download/${CASSETTEOS_VERSION}/uninstall.sh"
readonly CASSETTE_UNINSTALL_PATH=/usr/bin/cassetteos-uninstall

# REQUIREMENTS CONF PATH
# Udevil
readonly UDEVIL_CONF_PATH=/etc/udevil/udevil.conf
readonly DEVMON_CONF_PATH=/etc/conf.d/devmon

# COLORS
readonly COLOUR_RESET='\e[0m'
readonly aCOLOUR=(
    '\e[38;5;154m' # green      | Lines, bullets and separators
    '\e[1m'        # Bold white | Main descriptions
    '\e[90m'       # Grey               | Credits
    '\e[91m'       # Red                | Update notifications Alert
    '\e[33m'       # Yellow             | Emphasis
)

readonly GREEN_LINE=" ${aCOLOUR[0]}─────────────────────────────────────────────────────$COLOUR_RESET"
readonly GREEN_BULLET=" ${aCOLOUR[0]}-$COLOUR_RESET"
readonly GREEN_SEPARATOR="${aCOLOUR[0]}:$COLOUR_RESET"

# CASSETTEOS VARIABLES
TARGET_ARCH=""
TMP_ROOT=/tmp/cassetteos-installer
REGION="UNKNOWN"
CASSETTE_DOWNLOAD_DOMAIN="https://github.com/"
CONFIG_FILE="/etc/cassetteos/cassetteos.conf"
INTERFACE=$(sudo iw dev | awk '$1=="Interface"{print $2}')
trap 'onCtrlC' INT
onCtrlC() {
    echo -e "${COLOUR_RESET}"
    exit 1
}

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
        exit 1
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

GreyStart() {
    echo -e "${aCOLOUR[2]}\c"
}

ColorReset() {
    echo -e "$COLOUR_RESET\c"
}

# Clear Terminal
Clear_Term() {

    # Without an input terminal, there is no point in doing this.
    [[ -t 0 ]] || return

    # Printing terminal height - 1 newlines seems to be the fastest method that is compatible with all terminal types.
    lines=$(tput lines) i newlines
    local lines

    for ((i = 1; i < ${lines% *}; i++)); do newlines+='\n'; done
    echo -ne "\e[0m$newlines\e[H"

}

# Check file exists
exist_file() {
    if [ -e "$1" ]; then
        return 1
    else
        return 2
    fi
}

###############################################################################
# FUNCTIONS                                                                   #
###############################################################################

# 1 Check Arch
Check_Arch() {
    case $UNAME_M in
    *aarch64*)
        TARGET_ARCH="arm64"
        ;;
    *64*)
        TARGET_ARCH="amd64"
        ;;
    *armv7*)
        TARGET_ARCH="arm-7"
        ;;
    *)
        Show 1 "Aborted, unsupported or unknown architecture: $UNAME_M"
        exit 1
        ;;
    esac
    Show 0 "Your hardware architecture is : $UNAME_M"
    CASSETTE_PACKAGES=(
        "${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-Gateway/releases/download/${CASSETTEOS_VERSION}/linux-${TARGET_ARCH}-cassetteos-gateway-${CASSETTEOS_VERSION}.tar.gz"
"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-MessageBus/releases/download/${CASSETTEOS_VERSION}/linux-${TARGET_ARCH}-cassetteos-message-bus-${CASSETTEOS_VERSION}.tar.gz"
"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-UserService/releases/download/${CASSETTEOS_VERSION}/linux-${TARGET_ARCH}-cassetteos-user-service-${CASSETTEOS_VERSION}.tar.gz"
"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-LocalStorage/releases/download/${CASSETTEOS_VERSION}/linux-${TARGET_ARCH}-cassetteos-local-storage-${CASSETTEOS_VERSION}.tar.gz"
"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-AppManagement/releases/download/${CASSETTEOS_VERSION}/linux-${TARGET_ARCH}-cassetteos-app-management-${CASSETTEOS_VERSION}.tar.gz"
"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS/releases/download/${CASSETTEOS_VERSION}/linux-${TARGET_ARCH}-cassetteos-${CASSETTEOS_VERSION}.tar.gz"
"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-CLI/releases/download/${CASSETTEOS_VERSION}/linux-${TARGET_ARCH}-cassetteos-cli-${CASSETTEOS_VERSION}.tar.gz"
"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-UI/releases/download/${CASSETTEOS_VERSION}/linux-all-cassetteos-${CASSETTEOS_VERSION}.tar.gz"
#"${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-AppStore/releases/download/v0.4.5/linux-all-appstore-v0.4.5.tar.gz" 

    )
}

# PACKAGE LIST OF CASSETTEOS (make sure the services are in the right order)
CASSETTE_SERVICES=(
    "cassetteos-gateway.service"
"cassetteos-message-bus.service"
"cassetteos-user-service.service"
"cassetteos-local-storage.service"
"cassetteos-app-management.service"
"cassetteos.service"  # must be the last one so update from UI can work 
)

# 2 Check Distribution
Check_Distribution() {
    sType=0
    notice=""
    case $LSB_DIST in
    *debian*) ;;

    *ubuntu*) ;;

    *raspbian*) ;;

    *openwrt*)
        Show 1 "Aborted, OpenWrt cannot be installed using this script."
        exit 1
        ;;
    *alpine*)
        Show 1 "Aborted, Alpine installation is not yet supported."
        exit 1
        ;;
    *trisquel*) ;;

    *)
        sType=3
        notice="We have not tested it on this system and it may fail to install."
        ;;
    esac
    Show ${sType} "Your Linux Distribution is : ${DIST} ${notice}"

    if [[ ${sType} == 1 ]]; then
        select yn in "Yes" "No"; do
            case $yn in
            [yY][eE][sS] | [yY])
                Show 0 "Distribution check has been ignored."
                break
                ;;
            [nN][oO] | [nN])
                Show 1 "Already exited the installation."
                exit 1
                ;;
            esac
        done < /dev/tty # < /dev/tty is used to read the input from the terminal
    fi
}

# 3 Check OS
Check_OS() {
    if [[ $UNAME_U == *Linux* ]]; then
        Show 0 "Your System is : $UNAME_U"
    else
        Show 1 "This script is only for Linux."
        exit 1
    fi
}

# 4 Check Memory
Check_Memory() {
    if [[ "${PHYSICAL_MEMORY}" -lt "${MINIMUM_MEMORY}" ]]; then
        Show 1 "requires atleast 400MB physical memory."
        exit 1
    fi
    Show 0 "Memory capacity check passed."
}

# 5 Check Disk
Check_Disk() {
    if [[ "${FREE_DISK_GB}" -lt "${MINIMUM_DISK_SIZE_GB}" ]]; then
        echo -e "${aCOLOUR[4]}Recommended free disk space is greater than ${MINIMUM_DISK_SIZE_GB}GB, Current free disk space is ${aCOLOUR[3]}${FREE_DISK_GB}GB${COLOUR_RESET}${aCOLOUR[4]}.\nContinue installation?${COLOUR_RESET}"
        select yn in "Yes" "No"; do
            case $yn in
            [yY][eE][sS] | [yY])
                Show 0 "Disk capacity check has been ignored."
                break
                ;;
            [nN][oO] | [nN])
                Show 1 "Already exited the installation."
                exit 1
                ;;
            esac
        done < /dev/tty  # < /dev/tty is used to read the input from the terminal
    else
        Show 0 "Disk capacity check passed."
    fi
}

# Check Port Use
Check_Port() {
    TCPListeningnum=$(${sudo_cmd} netstat -an | grep ":$1 " | awk '$1 == "tcp" && $NF == "LISTEN" {print $0}' | wc -l)
    UDPListeningnum=$(${sudo_cmd} netstat -an | grep ":$1 " | awk '$1 == "udp" && $NF == "0.0.0.0:*" {print $0}' | wc -l)
    ((Listeningnum = TCPListeningnum + UDPListeningnum))
    if [[ $Listeningnum == 0 ]]; then
        echo "0"
    else
        echo "1"
    fi
}

# Get an available port
Get_Port() {
    CurrentPort=$(${sudo_cmd} cat ${CASSETTE_CONF_PATH} | grep HttpPort | awk '{print $3}')
    if [[ $CurrentPort == "$Port" ]]; then
        for PORT in {80..65536}; do
            if [[ $(Check_Port "$PORT") == 0 ]]; then
                Port=$PORT
                break
            fi
        done
    else
        Port=$CurrentPort
    fi
}

# Update package

Update_Package_Resource() {
    Show 2 "Updating package manager..."
    GreyStart
    if [ -x "$(command -v apk)" ]; then
        ${sudo_cmd} apk update
    elif [ -x "$(command -v apt-get)" ]; then
        ${sudo_cmd} apt-get update -qq
    elif [ -x "$(command -v dnf)" ]; then
        ${sudo_cmd} dnf check-update
    elif [ -x "$(command -v zypper)" ]; then
        ${sudo_cmd} zypper update
    elif [ -x "$(command -v yum)" ]; then
        ${sudo_cmd} yum update
    fi
    ColorReset
    Show 0 "Update package manager complete."
}

Install_Depends() {
    local dep_list=("$@")

    for pair in "${dep_list[@]}"; do
        IFS=':' read -r cmd pkg <<< "$pair"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            Show 2 "Installing missing dependency: \e[33m$pkg\e[0m (for $cmd)"
            GreyStart
            if [ -x "$(command -v apk)" ]; then
                ${sudo_cmd} apk add --no-cache "$pkg"
            elif [ -x "$(command -v apt-get)" ]; then
                ${sudo_cmd} apt-get -y -qq install "$pkg" --no-upgrade
            elif [ -x "$(command -v dnf)" ]; then
                ${sudo_cmd} dnf install -y "$pkg"
            elif [ -x "$(command -v zypper)" ]; then
                ${sudo_cmd} zypper install -y "$pkg"
            elif [ -x "$(command -v yum)" ]; then
                ${sudo_cmd} yum install -y "$pkg"
            elif [ -x "$(command -v pacman)" ]; then
                ${sudo_cmd} pacman -S --noconfirm "$pkg"
            elif [ -x "$(command -v paru)" ]; then
                ${sudo_cmd} paru -S --noconfirm "$pkg"
            else
                Show 1 "Package manager not found. You must manually install: \e[33m$pkg\e[0m"
            fi
            ColorReset
        fi
    done
}

Check_Depends_Installed() {
    local dep_list=("$@")

    for pair in "${dep_list[@]}"; do
        IFS=':' read -r cmd pkg <<< "$pair"
        if ! command -v "$cmd" >/dev/null 2>&1; then
            Show 1 "Dependency \e[33m$pkg\e[0m (command: $cmd) is still missing after installation. Please check manually."
            exit 1
        fi
    done
}

# Check Docker running
Check_Docker_Running() {
    for ((i = 1; i <= 3; i++)); do
        sleep 3
        if [[ ! $(${sudo_cmd} systemctl is-active docker) == "active" ]]; then
            Show 1 "Docker is not running, try to start"
            ${sudo_cmd} systemctl start docker
        else
            break
        fi
    done
}

#Check Docker Installed and version
Check_Docker_Install() {
    if [[ -x "$(command -v docker)" ]]; then
        Docker_Version=$(${sudo_cmd} docker version --format '{{.Server.Version}}')
        if [[ $? -ne 0 ]]; then
            Install_Docker
        elif [[ ${Docker_Version:0:2} -lt "${MINIMUM_DOCKER_VERSION}" ]]; then
            Show 1 "Recommended minimum Docker version is \e[33m${MINIMUM_DOCKER_VERSION}.xx.xx\e[0m,\Current Docker version is \e[33m${Docker_Version}\e[0m,\nPlease uninstall current Docker and rerun the CassetteOS installation script."
            exit 1
        else
            Show 0 "Current Docker version is ${Docker_Version}."
        fi
    else
        Install_Docker
    fi
}

# Check Docker installed
Check_Docker_Install_Final() {
    if [[ -x "$(command -v docker)" ]]; then
        Docker_Version=$(${sudo_cmd} docker version --format '{{.Server.Version}}')
        if [[ $? -ne 0 ]]; then
            Install_Docker
        elif [[ ${Docker_Version:0:2} -lt "${MINIMUM_DOCKER_VERSION}" ]]; then
            Show 1 "Recommended minimum Docker version is \e[33m${MINIMUM_DOCKER_VERSION}.xx.xx\e[0m,\Current Docker version is \e[33m${Docker_Version}\e[0m,\nPlease uninstall current Docker and rerun the CassetteOS installation script."
            exit 1
        else
            Show 0 "Current Docker version is ${Docker_Version}."
            Check_Docker_Running
        fi
    else
        Show 1 "Installation failed, please run 'curl -fsSL https://get.docker.com | bash' and rerun the CassetteOS installation script."
        exit 1
    fi
}

#Install Docker
Install_Docker() {
    Show 2 "Install the necessary dependencies: \e[33mDocker \e[0m"
    if [[ ! -d "${PREFIX}/etc/apt/sources.list.d" ]]; then
        ${sudo_cmd} mkdir -p "${PREFIX}/etc/apt/sources.list.d"
    fi
    GreyStart
    ${sudo_cmd} curl -fsSL https://get.docker.com | bash
    ColorReset
    if [[ $? -ne 0 ]]; then
        Show 1 "Installation failed, please try again."
        exit 1
    else
        Check_Docker_Install_Final
    fi
}

#Configuration Addons
Configuration_Addons() {
    Show 2 "Configuration CassetteOS Addons"
    #Remove old udev rules
    if [[ -f "${PREFIX}/etc/udev/rules.d/11-usb-mount.rules" ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/etc/udev/rules.d/11-usb-mount.rules"
    fi

    if [[ -f "${PREFIX}/etc/systemd/system/usb-mount@.service" ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/etc/systemd/system/usb-mount@.service"
    fi

    #Udevil
    if [[ -f $PREFIX${UDEVIL_CONF_PATH} ]]; then

        # GreyStart
        # Add a devmon user
        USERNAME=devmon
        id ${USERNAME} &>/dev/null || {
            ${sudo_cmd} useradd -M -u 300 ${USERNAME}
            ${sudo_cmd} usermod -L ${USERNAME}
        }

        ${sudo_cmd} sed -i '/exfat/s/, nonempty//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/default_options/s/, noexec//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/^ARGS/cARGS="--mount-options nosuid,nodev,noatime --ignore-label EFI"' "$PREFIX"${DEVMON_CONF_PATH}

        # Add and start Devmon service
        GreyStart
        ${sudo_cmd} systemctl enable devmon@devmon
        ${sudo_cmd} systemctl start devmon@devmon
        ColorReset
        # ColorReset
    fi
}

# Download And Install CassetteOS
DownloadAndInstallCassetteOS() {
    if [ -z "${BUILD_DIR}" ]; then
        ${sudo_cmd} rm -rf ${TMP_ROOT}
        mkdir -p ${TMP_ROOT} || Show 1 "Failed to create temporary directory"
        TMP_DIR=$(${sudo_cmd} mktemp -d -p ${TMP_ROOT} || Show 1 "Failed to create temporary directory")

        pushd "${TMP_DIR}"

        for PACKAGE in "${CASSETTE_PACKAGES[@]}"; do
            Show 2 "Downloading ${PACKAGE}..."
            GreyStart
            ${sudo_cmd} wget -t 3 -q --show-progress -c  "${PACKAGE}" || Show 1 "Failed to download package"
            ColorReset
        done

        for PACKAGE_FILE in linux-*.tar.gz; do
            Show 2 "Extracting ${PACKAGE_FILE}..."
            GreyStart
            ${sudo_cmd} tar zxf "${PACKAGE_FILE}" || Show 1 "Failed to extract package"
            ColorReset
        done

        BUILD_DIR=$(${sudo_cmd} realpath -e "${TMP_DIR}"/build || Show 1 "Failed to find build directory")

        popd
    fi

    for SERVICE in "${CASSETTE_SERVICES[@]}"; do
        if ${sudo_cmd} systemctl --quiet is-active "${SERVICE}"; then
            Show 2 "Stopping ${SERVICE}..."
            GreyStart
            ${sudo_cmd} systemctl stop "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."
            ColorReset
        fi
    done
    
    Show 2 "Installing CassetteOS..."
    SYSROOT_DIR=$(realpath -e "${BUILD_DIR}"/sysroot || Show 1 "Failed to find sysroot directory")

    # Generate manifest for uninstallation
    MANIFEST_FILE=${BUILD_DIR}/sysroot/var/lib/cassetteos/manifest
    ${sudo_cmd} touch "${MANIFEST_FILE}" || Show 1 "Failed to create manifest file"

    GreyStart
    find "${SYSROOT_DIR}" -type f | ${sudo_cmd} cut -c ${#SYSROOT_DIR}- | ${sudo_cmd} cut -c 2- | ${sudo_cmd} tee "${MANIFEST_FILE}" >/dev/null || Show 1 "Failed to create manifest file"#

    ${sudo_cmd} cp -rf "${SYSROOT_DIR}"/* / || Show 1 "Failed to install CassetteOS"
    ColorReset

    SETUP_SCRIPT_DIR=$(realpath -e "${BUILD_DIR}"/scripts/setup/script.d || Show 1 "Failed to find setup script directory")

    for SETUP_SCRIPT in "${SETUP_SCRIPT_DIR}"/*.sh; do
        Show 2 "Running ${SETUP_SCRIPT}..."
        GreyStart
        ${sudo_cmd} bash "${SETUP_SCRIPT}" || Show 1 "Failed to run setup script"
        ColorReset
    done
    
    UI_EVENTS_REG_SCRIPT=/etc/cassetteos/start.d/register-ui-events.sh
    if [[ -f ${UI_EVENTS_REG_SCRIPT} ]]; then
        ${sudo_cmd} chmod +x $UI_EVENTS_REG_SCRIPT
    fi
    
    # Download Uninstall Script
    if [[ -f $PREFIX/tmp/cassetteos-uninstall ]]; then
        ${sudo_cmd} rm -rf "$PREFIX/tmp/cassetteos-uninstall"
    fi
    ${sudo_cmd} curl -fsSLk "$CASSETTE_UNINSTALL_URL" >"$PREFIX/tmp/cassetteos-uninstall"
    ${sudo_cmd} cp -rf "$PREFIX/tmp/cassetteos-uninstall" $CASSETTE_UNINSTALL_PATH || {
       Show 1 "Download uninstall script failed, Please check if your internet connection is working and retry."
       exit 1
    }

    ${sudo_cmd} chmod +x $CASSETTE_UNINSTALL_PATH
    
    for SERVICE in "${CASSETTE_SERVICES[@]}"; do
       Show 2 "Starting ${SERVICE}..."
       GreyStart
       ${sudo_cmd} systemctl start "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."
       ColorReset
   done
}

Clean_Temp_Files() {
    Show 2 "Clean temporary files..."
    ${sudo_cmd} rm -rf "${TMP_DIR}" || Show 1 "Failed to clean temporary files"
}

Check_Service_status() {
    for SERVICE in "${CASSETTE_SERVICES[@]}"; do
        Show 2 "Checking ${SERVICE}..."
        if [[ $(${sudo_cmd} systemctl is-active "${SERVICE}") == "active" ]]; then
            Show 0 "${SERVICE} is running."
        else
            Show 1 "${SERVICE} is not running, Please reinstall."
            exit 1
        fi
    done
}

# Get the physical NIC IP
Get_IPs() {
    PORT=$(${sudo_cmd} cat ${CASSETTE_CONF_PATH} | grep port | sed 's/port=//')
    ALL_NIC=$($sudo_cmd ls /sys/class/net/ | grep -v "$(ls /sys/devices/virtual/net/)")
    for NIC in ${ALL_NIC}; do
        IP=$($sudo_cmd ifconfig "${NIC}" | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | sed -e 's/addr://g')
        if [[ -n $IP ]]; then
            if [[ "$PORT" -eq "80" ]]; then
                echo -e "${GREEN_BULLET} http://$IP (${NIC})"
            else
                echo -e "${GREEN_BULLET} http://$IP:$PORT (${NIC})"
            fi
        fi
    done
}

# Show Welcome Banner
Welcome_Banner() {
    CASSETTE_TAG=$(cassetteos -v)

    echo -e "${GREEN_LINE}${aCOLOUR[1]}"
    echo -e " CassetteOS ${CASSETTE_TAG}${COLOUR_RESET} is running at${COLOUR_RESET}${GREEN_SEPARATOR}"
    echo -e "${GREEN_LINE}"
    Get_IPs
    echo -e " Open your browser and visit the above address."
    echo -e "${GREEN_LINE}"
    echo -e ""
    echo -e " ${aCOLOUR[2]}CassetteOS Project  : https://github.com/BeesNestInc/CassetteOS"
    echo -e ""
    echo -e " ${COLOUR_RESET}${aCOLOUR[1]}Uninstall       ${COLOUR_RESET}: cassetteos-uninstall"
    echo -e "${COLOUR_RESET}"
}
set_ini_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    # セクションが存在しない場合は末尾に追加
    if ! grep -q "^\[$section\]" "$file"; then
        echo -e "\n[$section]" >> "$file"
    fi

    # セクション行の行番号取得
    local section_line
    section_line=$(grep -n "^\[$section\]" "$file" | cut -d: -f1 | head -n1)

    # セクションの次に同じキーが存在するか確認
    if awk -v s="$section" -v k="$key" '
        $0 ~ "\\[" s "\\]" { in_section=1; next }
        /^\[.*\]/ { in_section=0 }
        in_section && $1 == k { found=1 }
        END { exit !found }
    ' "$file"; then
        # 上書き
        sed -i "/^\[$section\]/, /^\[.*\]/ s|^$key *=.*|$key = $value|" "$file"
    else
        # セクション直下に追記
        sed -i "$((section_line + 1)) i$key = $value" "$file"
    fi
}

Configure_PgHba() {
    local PG_HBA
    PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW hba_file;' 2>/dev/null)

    if [ -z "$PG_HBA" ] || [ ! -f "$PG_HBA" ]; then
        Show 1 "pg_hba.conf not found via PostgreSQL. Is it installed and initialized?"
        return 1
    fi

    Show 2 "Creating backup of pg_hba.conf..."
    ${sudo_cmd} cp "$PG_HBA" "${PG_HBA}.bak"

    local RULES="
# Added by CassetteOS installer
host    all             db_admin_user   172.30.0.0/16            trust
host    all             all             172.30.0.0/16           md5
"
    if ! grep -q "172.30.0.0/16" "$PG_HBA"; then
        Show 2 "Appending Docker access rules to pg_hba.conf..."
        echo "$RULES" | ${sudo_Gcmd} tee -a "$PG_HBA" >/dev/null
    else
        Show 2 "Docker access rules already exist in pg_hba.conf. Skipping."
    fi
}
Configure_Postgres_ListenAddresses() {
    local PG_CONF
    PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c 'SHOW config_file;' 2>/dev/null)

    if [ -z "$PG_CONF" ] || [ ! -f "$PG_CONF" ]; then
        Show 1 "postgresql.conf not found. Is PostgreSQL installed and initialized?"
        return 1
    fi

    Show 2 "Creating backup of postgresql.conf..."
    ${sudo_cmd} cp "$PG_CONF" "${PG_CONF}.bak"

    if grep -qE '^\s*listen_addresses\s*=' "$PG_CONF"; then
        Show 2 "Commenting out existing active listen_addresses line..."
        ${sudo_cmd} sed -i.bak '/^\s*listen_addresses\s*=/{s/^/#/}' "$PG_CONF"
    else
        Show 2 "No active listen_addresses line found, skipping comment-out."
    fi

    Show 2 "Appending listen_addresses='*' to postgresql.conf..."
    echo "listen_addresses='*'" | ${sudo_cmd} tee -a "$PG_CONF" >/dev/null
}
Install_DbAdmin_StoredProcedure() {
    local SCRIPT_URL="https://github.com/BeesNestInc/CassetteOS-Tools/releases/download/${CASSETTEOS_VERSION}/db_setup.sql"
    local SCRIPT_PATH="/tmp/db_setup.sql"

    Show 2 "Downloading db_admin_user setup script from: $SCRIPT_URL"
    if ! curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH"; then
        Show 1 "Failed to download DB setup script!"
        return 1
    fi

    Show 2 "Executing DB setup script..."
    if ! sudo -u postgres psql -f "$SCRIPT_PATH"; then
        Show 1 "Failed to execute DB setup script!"
        return 1
    fi

    Show 2 "DB admin setup script completed successfully!"
}
Restart_Postgres_Service() {
    ${sudo_cmd} systemctl stop postgresql
    ${sudo_cmd} systemctl start postgresql
    Show 2 "PostgreSQL restarted."
}

Configure_host_database(){
    echo "🔧 Setting up connection to host database..."
    Install_Depends "${HOST_DB_DEPENDS_LIST[@]}"
    Check_Depends_Installed "${HOST_DB_DEPENDS_LIST[@]}"

    # configure postgres
    Configure_PgHba #pending md5 for db_admin_user
    Configure_Postgres_ListenAddresses

    # pending: create password and save /etc/cassettesos/env
    # pending: append password to download script

    # install create_user 
    Install_DbAdmin_StoredProcedure

    # service stop and start
    Restart_Postgres_Service
}
Create_Hostapd_Config(){
    local HOSTAPD_CONF="/etc/hostapd/hostapd.conf"

    echo "🔧 Creating hostapd.conf..."


    [ -f "$HOSTAPD_CONF" ] && sudo cp "$HOSTAPD_CONF" "$HOSTAPD_CONF.bak.$(date +%s)"
    
    # SSIDとパスワードを取得
    read -p "📶 Enter SSID for AP [default: Setup-WiFi]: " SSID
    SSID=${SSID:-Setup-WiFi}

    read -s -p "🔑 Enter WPA passphrase [default: SetupMe1234]: " PASSPHRASE
    echo ""
    PASSPHRASE=${PASSPHRASE:-SetupMe1234}

    # 設定ファイル生成
    sudo tee "$HOSTAPD_CONF" > /dev/null <<EOF
interface=$INTERFACE
ssid=$SSID
hw_mode=g
channel=6
auth_algs=1
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
country_code=JP
ieee80211d=1
ieee80211n=1
wmm_enabled=1
EOF

    echo "✅ Created $HOSTAPD_CONF"
}
Create_Dnsmasq_Config(){
    local DNSMASQ_CONF="/etc/dnsmasq.conf"

    echo "🛠 Creating dnsmasq.conf..."

    [ -f "$DNSMASQ_CONF" ] && sudo cp "$DNSMASQ_CONF" "$DNSMASQ_CONF.bak.$(date +%s)"

    sudo tee "$DNSMASQ_CONF" > /dev/null <<EOF
interface=$INTERFACE
bind-interfaces
dhcp-range=192.168.4.100,192.168.4.200,12h
dhcp-option=3,192.168.4.1
dhcp-option=6,192.168.4.1
server=8.8.8.8
server=1.1.1.1
log-queries
log-dhcp
listen-address=192.168.4.1
listen-address=127.0.0.1
address=/msftconnecttest.com/192.168.4.1
EOF

    echo "✅ Created $DNSMASQ_CONF"
}


Configure_wifi_access(){
    echo "📡 Setting up WiFi access configuration..."
    Install_Depends "${WIFI_SETUP_DEPENDS_LIST[@]}"
    Check_Depends_Installed "${WIFI_SETUP_DEPENDS_LIST[@]}"

    sudo systemctl unmask hostapd

    Create_Hostapd_Config
    Create_Dnsmasq_Config

    echo "Do you want to switch to AP mode now? [y/N]"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "🔁 Switching to AP mode..."
        sudo bash /usr/share/cassetteos/shell/switch-wifi-mode.sh ap
    else
        echo "⏩ Skipping AP mode switch."
    fi
}
###############################################################################
# Main                                                                        #
###############################################################################

#Usage
usage() {
    cat <<-EOF
                Usage: install.sh [options]
                Valid options are:
                    -p <build_dir>          Specify build directory (Local install)
                    -h                      Show this help message and exit
EOF
    exit "$1"
}

while getopts ":p:HWh" arg; do
    case "$arg" in
    p)
        BUILD_DIR=$OPTARG
        ;;
    h)
        usage 0
        ;;
    *)
        usage 1
        ;;
    esac
done

# Step 1: Check ARCH
Check_Arch

# Step 2: Check OS
Check_OS

# Step 3: Check Distribution
Check_Distribution

# Step 4: Check System Required
Check_Memory
Check_Disk

# Step 5: Install Depends

Update_Package_Resource
Install_Depends "${CASSETTE_DEPENDS_LIST[@]}"
Check_Depends_Installed "${CASSETTE_DEPENDS_LIST[@]}"

# Step 6: Check And Install Docker
Check_Docker_Install


# Step 7: Configuration Addon
Configuration_Addons

# Step 8: Download And Install CassetteOS
DownloadAndInstallCassetteOS

Configure_host_database
set_ini_value "$CONFIG_FILE" "app" "EnableHostDB" "true"

if [[ -z "$INTERFACE" ]]; then
    echo "❌ No wireless interface found. Aborting."
    set_ini_value "$CONFIG_FILE" "app" "EnableWifiSetup" "false"
else
    Configure_wifi_access
    set_ini_value "$CONFIG_FILE" "app" "EnableWifiSetup" "true"
fi

echo "CassetteOS Restarting...."
${sudo_cmd} systemctl stop "cassetteos.service"
${sudo_cmd} systemctl start "cassetteos.service"

# Step 9: Check Service Status
Check_Service_status

# Step 10: Clear Term and Show Welcome Banner
Welcome_Banner