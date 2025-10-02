#!/usr/bin/bash
#
#           CassetteOS Update Script v0.0.10
#   GitHub: https://github.com/BeesNestInc/CassetteOS
#   Requires: bash, mv, rm, tr, grep, sed, curl/wget, tar, smartmontools, parted, ntfs-3g, net-tools
# 
#   This script update your CassetteOS.
#   Usage:
#
#       $ wget -qO- https://github.com/BeesNestInc/CassetteOS-Tools/releases/download/v0.0.10/update.sh | sudo bash
#         or
#       $ curl -fsSL https://github.com/BeesNestInc/CassetteOS-Tools/releases/download/v0.0.10/update.sh | sudo bash
#
#   In automated environments, you may want to run as root.
#   If using curl, we recommend using the -fsSL flags.
#
#   This only work on  Linux systems. Please
#   open an issue if you notice any bugs.
#


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
set -e

###############################################################################
# GOLBALS                                                                     #
###############################################################################

# version
readonly CASSETTEOS_VERSION="v0.0.10"

((EUID)) && sudo_cmd="sudo"

# shellcheck source=/dev/null
source /etc/os-release

# SYSTEM REQUIREMENTS
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

LSB_DIST=$( ( [ -n "${ID_LIKE}" ] && echo "${ID_LIKE}" ) || ( [ -n "${ID}" ] && echo "${ID}" ) )
readonly LSB_DIST

UNAME_M="$(uname -m)"
readonly UNAME_M

readonly CASSETTE_UNINSTALL_URL="https://github.com/BeesNestInc/CassetteOS-Tools/releases/download/${CASSETTEOS_VERSION}/uninstall.sh"
readonly CASSETTE_UNINSTALL_PATH=/usr/bin/cassetteos-uninstall

# REQUIREMENTS CONF PATH
# Udevil
readonly UDEVIL_CONF_PATH=/etc/udevil/udevil.conf
readonly DEVMON_CONF_PATH=/etc/conf.d/devmon
readonly APP_CONFIG_FILE=/etc/cassetteos/app-management.conf

# COLORS
readonly COLOUR_RESET='\e[0m'
readonly aCOLOUR=(
    '\e[38;5;154m' # green  	| Lines, bullets and separators
    '\e[1m'        # Bold white	| Main descriptions
    '\e[90m'       # Grey		| Credits
    '\e[91m'       # Red		| Update notifications Alert
    '\e[33m'       # Yellow		| Emphasis
)


# CASSETTEOS VARIABLES
TARGET_ARCH=""
TMP_ROOT=/tmp/cassetteos-installer
CASSETTE_DOWNLOAD_DOMAIN="https://github.com/"

# PACKAGE LIST OF CASSETTEOS
CASSETTE_SERVICES=(
    "cassetteos-gateway.service"
"cassetteos-message-bus.service"
"cassetteos-user-service.service"
"cassetteos-local-storage.service"
"cassetteos-app-management.service"
"cassetteos.service"  # must be the last one so update from UI can work 
)


trap 'onCtrlC' INT
onCtrlC() {
    echo -e "${COLOUR_RESET}"
    exit 1
}

# Set up a temporary directory and ensure it's cleaned up on exit
echo "Creating temporary directory..."
TMP_ROOT=/tmp/cassetteos-updater
${sudo_cmd} mkdir -p ${TMP_ROOT} || { echo "Failed to create temp root. Exiting."; exit 1; }
TMP_DIR=$(${sudo_cmd} mktemp -d -p ${TMP_ROOT} || { echo "Failed to create temp dir. Exiting."; exit 1; })
trap 'echo "Cleaning up temporary files..."; ${sudo_cmd} rm -rf "$TMP_ROOT"' EXIT


upgradePath="/var/log/cassetteos"
upgradeFile="/var/log/cassetteos/upgrade.log"

if [ -f "$upgradePath" ]; then
    ${sudo_cmd} rm "$upgradePath"
fi

if [ ! -d "$upgradePath" ]; then
    ${sudo_cmd} mkdir -p "$upgradePath"
fi

if [ ! -f "$upgradeFile" ]; then
    ${sudo_cmd} touch "$upgradeFile"
fi

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
    	echo -e "- OK $2" | ${sudo_cmd} tee -a /var/log/cassetteos/upgrade.log
    # FAILED
    elif (($1 == 1)); then
     	echo -e "- FAILED $2" | ${sudo_cmd} tee -a /var/log/cassetteos/upgrade.log
	exit 1
    # INFO
    elif (($1 == 2)); then
    	echo -e "- INFO $2" | ${sudo_cmd} tee -a /var/log/cassetteos/upgrade.log
    # NOTICE
    elif (($1 == 3)); then
    	echo -e "- NOTICE $2" | ${sudo_cmd} tee -a /var/log/cassetteos/upgrade.log
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

# Check file exists
exist_file() {
    if [ -e "$1" ]; then
        return 1
    else
        return 2
    fi
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
    )
}

# 2 Check Distribution
Check_Distribution() {
    sType=0
    notice=""
    case $LSB_DIST in
    *debian*)
        ;;
    *ubuntu*)
        ;;
    *raspbian*)
        ;;
    *openwrt*)
        Show 1 "Aborted, OpenWrt cannot be installed using this script, please visit ${CASSETTE_OPENWRT_DOCS}."
        exit 1
        ;;
    *alpine*)
        Show 1 "Aborted, Alpine installation is not yet supported."
        exit 1
        ;;
    *trisquel*)
        ;;
    *)
        sType=3
        notice="We have not tested it on this system and it may fail to install."
        ;;
    esac
    Show ${sType} "Your Linux Distribution is : ${LSB_DIST} ${notice}"
    if [[ ${sType} == 0 ]]; then
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
        done
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

# Update package

Update_Package_Resource() {
    GreyStart
    if [ -x "$(command -v apk)" ]; then
        ${sudo_cmd} apk update
    elif [ -x "$(command -v apt-get)" ]; then
        ${sudo_cmd} apt-get update --allow-releaseinfo-change
    elif [ -x "$(command -v dnf)" ]; then
        ${sudo_cmd} dnf check-update
    elif [ -x "$(command -v zypper)" ]; then
        ${sudo_cmd} zypper update
    elif [ -x "$(command -v yum)" ]; then
        ${sudo_cmd} yum update
    fi
    ColorReset
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
    if [[ -f "${PREFIX}${UDEVIL_CONF_PATH}" ]]; then

        # Revert previous CassetteOS udevil configuration
        #shellcheck disable=SC2016
        ${sudo_cmd} sed -i 's/allowed_media_dirs = \/DATA, \/DATA\/$USER/allowed_media_dirs = \/media, \/media\/$USER, \/run\/media\/$USER/g' "${PREFIX}${UDEVIL_CONF_PATH}"
        ${sudo_cmd} sed -i '/exfat/s/, nonempty//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/default_options/s/, noexec//g' "$PREFIX"${UDEVIL_CONF_PATH}
        ${sudo_cmd} sed -i '/^ARGS/cARGS="--mount-options nosuid,nodev,noatime --ignore-label EFI"' "$PREFIX"${DEVMON_CONF_PATH}
        
        # GreyStart
        # Add a devmon user
        USERNAME=devmon
        id ${USERNAME} &>/dev/null || {
            ${sudo_cmd} useradd -M -u 300 ${USERNAME}
            ${sudo_cmd} usermod -L ${USERNAME}
        }

        # Add and start Devmon service
        GreyStart
        ${sudo_cmd} systemctl enable devmon@devmon
        ${sudo_cmd} systemctl start devmon@devmon
        ColorReset
        # ColorReset
    fi
}

Run_Migrations() {
    local migration_dir="$1"
    Show 2 "Checking for necessary migrations in $migration_dir..."
    
    local installed_version
    if ! command -v /usr/bin/cassetteos >/dev/null 2>&1; then
        Show 3 "CassetteOS executable not found, skipping migrations."
        return
    fi

    # Assuming 'cassetteos --version' returns something like "v0.0.9" or "cassetteos version v0.0.9"
    installed_version=$(${sudo_cmd} /usr/bin/cassetteos --version | grep -o -E 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    if [ -z "$installed_version" ]; then
        Show 3 "Could not determine installed CassetteOS version. Skipping migrations."
        return
    fi

    Show 2 "Installed version: $installed_version. Checking for migration scripts..."

    if [ ! -d "$migration_dir" ]; then
        Show 0 "No migration directory found. Nothing to do."
        return
    fi

    # Export helper functions and variables for migration scripts
    export -f Show
    export -f Warn
    export -f set_ini_value
    export APP_CONFIG_FILE
    export sudo_cmd

    for migration_file in $(ls "$migration_dir"/*.sh | sort -V); do
        migration_version=$(basename "$migration_file" .sh) # e.g., v0.0.10
        
        # Compare installed version with the version of the migration script
        if dpkg --compare-versions "${installed_version#v}" "lt" "${migration_version#v}"; then
            Show 2 "Applying migration: $migration_file"
            # Make sure script is executable
            ${sudo_cmd} chmod +x "$migration_file"
            if bash "$migration_file"; then
                Show 0 "Successfully applied migration $migration_file"
            else
                Show 1 "Failed to apply migration $migration_file"
                exit 1
            fi
        fi
    done

    Show 0 "All applicable migrations have been run."
}

Download_Migrations() {
    Show 2 "Downloading migration scripts..."
    local MIGRATION_URL="${CASSETTE_DOWNLOAD_DOMAIN}BeesNestInc/CassetteOS-Tools/releases/download/${CASSETTEOS_VERSION}/migration_scripts.tar.gz"

    # This function assumes that the main script has already created TMP_DIR.
    # If it fails to download, it will show a notice and return 1, allowing the update to continue.
    if [ -z "$TMP_DIR" ] || [ ! -d "$TMP_DIR" ]; then
        Show 1 "Temporary directory not available for migrations."
        exit 1
    fi

    pushd "${TMP_DIR}" > /dev/null

    Show 2 "Downloading from ${MIGRATION_URL}..."
    if ! ${sudo_cmd} wget -t 3 -q -O "migration_scripts.tar.gz" "${MIGRATION_URL}"; then
        Show 3 "Failed to download migration scripts. It might be that there are no migrations for this version. Skipping."
        popd > /dev/null
        return 1 # Use return code to signal Run_Migrations to skip
    fi

    Show 2 "Extracting migration scripts..."
    if ! ${sudo_cmd} tar zxf "migration_scripts.tar.gz"; then
        Show 1 "Failed to extract migration scripts."
        popd > /dev/null
        exit 1
    fi

    popd > /dev/null
    Show 0 "Migration scripts downloaded and extracted."
    return 0
}

# Download And Install CassetteOS
DownloadAndInstallCassetteOS() {

    if [ -z "${BUILD_DIR}" ]; then

        pushd "${TMP_DIR}" > /dev/null

        for PACKAGE in "${CASSETTE_PACKAGES[@]}"; do
            Show 2 "Downloading ${PACKAGE}..."
          
            ${sudo_cmd} wget -t 3 -q --show-progress -c  "${PACKAGE}" || Show 1 "Failed to download package"
            
        done

        for PACKAGE_FILE in linux-*.tar.gz; do
            Show 2 "Extracting ${PACKAGE_FILE}..."
            ${sudo_cmd} tar zxf "${PACKAGE_FILE}" || Show 1 "Failed to extract package"
        done

        BUILD_DIR=$(realpath -e "${TMP_DIR}"/build || Show 1 "Failed to find build directory")

        popd
    fi

    # for SERVICE in "${CASSETTE_SERVICES[@]}"; do
    #     Show 2 "Stopping ${SERVICE}..."

    #   systemctl stop "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."

    # done

    MIGRATION_SCRIPT_DIR=$(realpath -e "${BUILD_DIR}"/scripts/migration/script.d || Show 1 "Failed to find migration script directory")

    for MIGRATION_SCRIPT in "${MIGRATION_SCRIPT_DIR}"/*.sh; do
        Show 2 "Running ${MIGRATION_SCRIPT}..."

        ${sudo_cmd} bash "${MIGRATION_SCRIPT}" || Show 1 "Failed to run migration script"

    done

    Show 2 "Installing CassetteOS..."
    SYSROOT_DIR=$(realpath -e "${BUILD_DIR}"/sysroot || Show 1 "Failed to find sysroot directory")

    # Generate manifest for uninstallation
    MANIFEST_FILE=${BUILD_DIR}/sysroot/var/lib/cassetteos/manifest
    ${sudo_cmd} touch "${MANIFEST_FILE}" || Show 1 "Failed to create manifest file"

    find "${SYSROOT_DIR}" -type f | ${sudo_cmd} cut -c ${#SYSROOT_DIR}- | ${sudo_cmd} cut -c 2- | ${sudo_cmd} tee "${MANIFEST_FILE}" >/dev/null || Show 1 "Failed to create manifest file"
    
    # Remove old UI files.
    ${sudo_cmd} rm -rf /var/lib/cassetteos/www/*
    
    ${sudo_cmd} cp -rf "${SYSROOT_DIR}"/* / >> /dev/null || Show 1 "Failed to install CassetteOS"

    SETUP_SCRIPT_DIR=$(realpath -e "${BUILD_DIR}"/scripts/setup/script.d || Show 1 "Failed to find setup script directory")

    for SETUP_SCRIPT in "${SETUP_SCRIPT_DIR}"/*.sh; do
        Show 2 "Running ${SETUP_SCRIPT}..."
        ${sudo_cmd} bash "${SETUP_SCRIPT}" || Show 1 "Failed to run setup script"
    done
    
    # Reset Permissions
    UI_EVENTS_REG_SCRIPT=/etc/cassetteos/start.d/register-ui-events.sh
    if [[ -f ${UI_EVENTS_REG_SCRIPT} ]]; then
        ${sudo_cmd} chmod +x $UI_EVENTS_REG_SCRIPT
    fi
    
    #Download Uninstall Script
    if [[ -f ${PREFIX}/tmp/cassetteos-uninstall ]]; then
        ${sudo_cmd} rm -rf "${PREFIX}/tmp/cassetteos-uninstall"
    fi
    ${sudo_cmd} curl -fsSLk "$CASSETTE_UNINSTALL_URL" >"${PREFIX}/tmp/cassetteos-uninstall"
    ${sudo_cmd} cp -rvf "${PREFIX}/tmp/cassetteos-uninstall" $CASSETTE_UNINSTALL_PATH || {
        Show 1 "Download uninstall script failed, Please check if your internet connection is working and retry."
        exit 1
    }

    ${sudo_cmd} chmod +x $CASSETTE_UNINSTALL_PATH
    
    ## Special markings

    Show 0 "CassetteOS upgrade successfully"
    for SERVICE in "${CASSETTE_SERVICES[@]}"; do
        Show 2 "restart ${SERVICE}..."

        ${sudo_cmd} systemctl restart "${SERVICE}" || Show 3 "Service ${SERVICE} does not exist."

    done

    
}

###############################################################################
# Main                                                                        #
###############################################################################

#Usage
usage() {
    cat <<-EOF
		Usage: get.sh [options]
		Valid options are:
		    -p <builddir>           Specify build directory
		    -h                      Show this help message and exit
	EOF
    exit "$1"
}

while getopts ":p:h" arg; do
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

# Step 2: Install Depends
Update_Package_Resource
Install_Depends "${CASSETTE_DEPENDS_LIST[@]}"
Check_Depends_Installed "${CASSETTE_DEPENDS_LIST[@]}"

# Step 3: Configuration Addon
Configuration_Addons

# Step 3.5: Run Migrations
if Download_Migrations; then
    Run_Migrations "$TMP_DIR/migration"
fi

# Step 4: Download And Install CassetteOS
#DownloadAndInstallCassetteOS
