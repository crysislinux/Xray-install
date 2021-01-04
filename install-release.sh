#!/bin/bash

# The files installed by the script conform to the Filesystem Hierarchy Standard:
# https://wiki.linuxfoundation.org/lsb/fhs

# The URL of the script project is:
# https://github.com/crysislinux/Xray-install

# The URL of the script is:
# https://raw.githubusercontent.com/crysislinux/Xray-install/main/install-release.sh

# If the script executes incorrectly, go to:
# https://github.com/crysislinux/Xray-install/issues

# You can set this variable whatever you want in shell session right before running this script by issuing:
# export DAT_PATH='/usr/local/share/xray'
DAT_PATH=${DAT_PATH:-/usr/local/share/xray}

# You can set this variable whatever you want in shell session right before running this script by issuing:
# export JSON_PATH='/usr/local/etc/xray'
JSON_PATH=${JSON_PATH:-/usr/local/etc/xray}

# Set this variable only if you are starting xray with multiple configuration files:
# export JSONS_PATH='/usr/local/etc/xray'

# Set this variable only if you want this script to check all the systemd unit file:
# export check_all_service_files='yes'

# Gobal verbals
# Xray current version
CURRENT_VERSION=""
# Xray latest release version
RELEASE_LATEST=""
# Xray version will be installed
INSTALL_VERSION=""
# install
INSTALL='0'
# install-geodata
INSTALL_GEODATA='0'
# remove
REMOVE='0'
# help
HELP='0'
# check
CHECK='0'
# --force
FORCE='0'
# --beta
BETA='0'
# --install-user ?
INSTALL_USER=""
# --without-geodata
NO_GEODATA='0'
# --not-update-service
N_UP_SERVICE='0'
# --reinstall
REINSTALL='0'
# --version ?
SPECIFIED_VERSION=""
# --local ?
LOCAL_FILE=""
# --proxy ?
PROXY=""
# --purge
PURGE='0'

curl() {
  $(type -P curl) -L -q --retry 5 --retry-delay 10 --retry-max-time 60 "$@"
}

check_if_running_as_root() {
  # If you want to run as another user, please modify $EUID to be owned by this user
  if [[ "$EUID" -ne '0' ]]; then
    echo "error: You must run this script as root!"
    exit 1
  fi
}

identify_the_operating_system_and_architecture() {
  if [[ "$(uname)" == 'Linux' ]]; then
    case "$(uname -m)" in
      'i386' | 'i686')
        MACHINE='32'
        ;;
      'amd64' | 'x86_64')
        MACHINE='64'
        ;;
      'armv5tel')
        MACHINE='arm32-v5'
        ;;
      'armv6l')
        MACHINE='arm32-v6'
        ;;
      'armv7' | 'armv7l')
        MACHINE='arm32-v7a'
        ;;
      'armv8' | 'aarch64')
        MACHINE='arm64-v8a'
        ;;
      'mips')
        MACHINE='mips32'
        ;;
      'mipsle')
        MACHINE='mips32le'
        ;;
      'mips64')
        MACHINE='mips64'
        ;;
      'mips64le')
        MACHINE='mips64le'
        ;;
      'ppc64')
        MACHINE='ppc64'
        ;;
      'ppc64le')
        MACHINE='ppc64le'
        ;;
      'riscv64')
        MACHINE='riscv64'
        ;;
      's390x')
        MACHINE='s390x'
        ;;
      *)
        echo "error: The architecture is not supported."
        exit 1
        ;;
    esac
    if [[ ! -f '/etc/os-release' ]]; then
      echo "error: Don't use outdated Linux distributions."
      exit 1
    fi
    
    if [[ "$(type -P apt)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='apt -y --no-install-recommends install'
      PACKAGE_MANAGEMENT_REMOVE='apt purge'
      package_provide_tput='ncurses-bin'
    elif [[ "$(type -P dnf)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='dnf -y install'
      PACKAGE_MANAGEMENT_REMOVE='dnf remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P yum)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='yum -y install'
      PACKAGE_MANAGEMENT_REMOVE='yum remove'
      package_provide_tput='ncurses'
    elif [[ "$(type -P zypper)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='zypper install -y --no-recommends'
      PACKAGE_MANAGEMENT_REMOVE='zypper remove'
      package_provide_tput='ncurses-utils'
    elif [[ "$(type -P pacman)" ]]; then
      PACKAGE_MANAGEMENT_INSTALL='pacman -Syu --noconfirm'
      PACKAGE_MANAGEMENT_REMOVE='pacman -Rsn'
      package_provide_tput='ncurses'
    else
      echo "error: The script does not support the package manager in this operating system."
      exit 1
    fi
  else
    echo "error: This operating system is not supported."
    exit 1
  fi
}

install_software() {
  package_name="$1"
  file_to_detect="$2"
  type -P "$file_to_detect" > /dev/null 2>&1 && return
  if ${PACKAGE_MANAGEMENT_INSTALL} "$package_name"; then
    echo "info: $package_name is installed."
  else
    echo "error: Installation of $package_name failed, please check your network."
    exit 1
  fi
}

get_current_version() {
  # Get the CURRENT_VERSION
  if [[ -f '/usr/local/bin/xray' ]]; then
    CURRENT_VERSION="$(/usr/local/bin/xray -version | awk 'NR==1 {print $2}')"
    CURRENT_VERSION="v${CURRENT_VERSION#v}"
  else
    CURRENT_VERSION=""
  fi
}

get_latest_version() {
  # Get Xray latest release version number
  TMP_FILE="$(mktemp)"
  if ! curl -x "${PROXY}" -sS -H "Accept: application/vnd.github.v3+json" -o "$TMP_FILE" 'https://api.github.com/repos/XTLS/Xray-core/releases/latest'; then
    "rm" "$TMP_FILE"
    echo 'error: Failed to get release list, please check your network.'
    exit 1
  fi
  RELEASE_LATEST="$(sed 'y/,/\n/' "$TMP_FILE" | grep 'tag_name' | awk -F '"' '{print $4}')"
  if [[ -z "$RELEASE_LATEST" ]]; then
    if grep -q "API rate limit exceeded" "$TMP_FILE"; then
      echo "error: github API rate limit exceeded"
    else
      echo "error: Failed to get the latest release version."
      echo "Welcome bug report:https://github.com/XTLS/Xray-install/issues"
    fi
    "rm" "$TMP_FILE"
    exit 1
  fi
  "rm" "$TMP_FILE"
  RELEASE_LATEST="v${RELEASE_LATEST#v}"
  if ! curl -x "${PROXY}" -sS -H "Accept: application/vnd.github.v3+json" -o "$TMP_FILE" 'https://api.github.com/repos/XTLS/Xray-core/releases'; then
    "rm" "$TMP_FILE"
    echo 'error: Failed to get release list, please check your network.'
    exit 1
  fi
  local releases_list=($(sed 'y/,/\n/' "$TMP_FILE" | grep 'tag_name' | awk -F '"' '{print $4}'))
  if [[ -z "${releases_list[@]}" ]]; then
    if grep -q "API rate limit exceeded" "$TMP_FILE"; then
      echo "error: github API rate limit exceeded"
    else
      echo "error: Failed to get the latest release version."
      echo "Welcome bug report:https://github.com/XTLS/Xray-install/issues"
    fi
    "rm" "$TMP_FILE"
    exit 1
  fi
  local i
  for i in ${!releases_list[@]}
  do
    releases_list[$i]="v${releases_list[$i]#v}"
    grep -q "https://github.com/XTLS/Xray-core/releases/download/${releases_list[$i]}/Xray-linux-$MACHINE.zip" "$TMP_FILE" && break
  done
  "rm" "$TMP_FILE"
  PRE_RELEASE_LATEST="${releases_list[$i]}"
}

version_gt() {
  # compare two version
  # 0: $1 >  $2
  # 1: $1 <= $2

  if [[ "$1" != "$2" ]]; then
    local temp_1_version_number="${1#v}"
    local temp_1_major_version_number="${temp_1_version_number%%.*}"
    local temp_1_minor_version_number="$(echo "$temp_1_version_number" | awk -F '.' '{print $2}')"
    local temp_1_minimunm_version_number="${temp_1_version_number##*.}"
    # shellcheck disable=SC2001
    local temp_2_version_number="${2#v}"
    local temp_2_major_version_number="${temp_2_version_number%%.*}"
    local temp_2_minor_version_number="$(echo "$temp_2_version_number" | awk -F '.' '{print $2}')"
    local temp_2_minimunm_version_number="${temp_2_version_number##*.}"
    if [[ "$temp_1_major_version_number" -gt "$temp_2_major_version_number" ]]; then
      return 0
    elif [[ "$temp_1_major_version_number" -eq "$temp_2_major_version_number" ]]; then
      if [[ "$temp_1_minor_version_number" -gt "$temp_2_minor_version_number" ]]; then
        return 0
      elif [[ "$temp_1_minor_version_number" -eq "$temp_2_minor_version_number" ]]; then
        if [[ "$temp_1_minimunm_version_number" -gt "$temp_2_minimunm_version_number" ]]; then
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    else
      return 1
    fi
  elif [[ "$1" == "$2" ]]; then
    return 1
  fi
}

download_xray() {
  DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/download/$INSTALL_VERSION/Xray-linux-$MACHINE.zip"
  echo "Downloading Xray archive: $DOWNLOAD_LINK"
  if ! curl -x "${PROXY}" -R -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK"; then
    echo 'error: Download failed! Please check your network or try again.'
    return 1
  fi
  return 0
  echo "Downloading verification file for Xray archive: $DOWNLOAD_LINK.dgst"
  if ! curl -x "${PROXY}" -sSR -H 'Cache-Control: no-cache' -o "$ZIP_FILE.dgst" "$DOWNLOAD_LINK.dgst"; then
    echo 'error: Download failed! Please check your network or try again.'
    return 1
  fi
  if [[ "$(cat "$ZIP_FILE".dgst)" == 'Not Found' ]]; then
    echo 'error: This version does not support verification. Please replace with another version.'
    return 1
  fi

  # Verification of Xray archive
  for LISTSUM in 'md5' 'sha1' 'sha256' 'sha512'; do
    SUM="$(${LISTSUM}sum "$ZIP_FILE" | sed 's/ .*//')"
    CHECKSUM="$(grep ${LISTSUM^^} "$ZIP_FILE".dgst | grep "$SUM" -o -a | uniq)"
    if [[ "$SUM" != "$CHECKSUM" ]]; then
      echo 'error: Check failed! Please check your network or try again.'
      return 1
    fi
  done
}

decompression() {
  if ! unzip -q "$1" -d "$TMP_DIRECTORY"; then
    echo 'error: Xray decompression failed.'
    "rm" -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    exit 1
  fi
  echo "info: Extract the Xray package to $TMP_DIRECTORY and prepare it for installation."
}

install_file() {
  NAME="$1"
  if [[ "$NAME" == 'xray' ]]; then
    install -m 755 "${TMP_DIRECTORY}/$NAME" "/usr/local/bin/$NAME"
  fi
}

install_xray() {
  # Install Xray binary to /usr/local/bin/
  install_file xray
}

main() {
  check_if_running_as_root
  identify_the_operating_system_and_architecture

  install_software "$package_provide_tput" 'tput'
  red=$(tput setaf 1)
  green=$(tput setaf 2)
  aoi=$(tput setaf 6)
  reset=$(tput sgr0)

  # Two very important variables
  TMP_DIRECTORY="$(mktemp -d)"
  ZIP_FILE="${TMP_DIRECTORY}/Xray-linux-$MACHINE.zip"

  # Install Xray from a local file, but still need to make sure the network is available
  if [[ -n "$LOCAL_FILE" ]]; then
    echo 'warn: Install Xray from a local file, but still need to make sure the network is available.'
    echo -n 'warn: Please make sure the file is valid because we cannot confirm it. (Press any key) ...'
    read -r
    install_software 'unzip' 'unzip'
    decompression "$LOCAL_FILE"
  else
    get_current_version
    if [[ "$REINSTALL" -eq '1' ]]; then
      if [[ -z "$CURRENT_VERSION" ]]; then
        echo "error: Xray is not installed"
        exit 1
      fi
      INSTALL_VERSION="$CURRENT_VERSION"
      echo "info: Reinstalling Xray $CURRENT_VERSION"
    elif [[ -n "$SPECIFIED_VERSION" ]]; then
      SPECIFIED_VERSION="v${SPECIFIED_VERSION#v}"
      if [[ "$CURRENT_VERSION" == "$SPECIFIED_VERSION" ]] && [[ "$FORCE" -eq '0' ]]; then
        echo "info: The current version is same as the specified version. The version is $CURRENT_VERSION ."
        exit 0
      fi
      INSTALL_VERSION="$SPECIFIED_VERSION"
      echo "info: Installing specified Xray version $INSTALL_VERSION for $(uname -m)"
    else
      install_software 'curl' 'curl'
      get_latest_version
      if [[ "$BETA" -eq '0' ]]; then
        INSTALL_VERSION="$RELEASE_LATEST"
      else
        INSTALL_VERSION="$PRE_RELEASE_LATEST"
      fi
      version_gt $INSTALL_VERSION $CURRENT_VERSION
      local temp_number=$?
      if [[ "$temp_number" -eq '1' ]] && [[ "$FORCE" -eq '0' ]]; then
        echo "info: No new version. The current version of Xray is $CURRENT_VERSION ."
        exit 0
      fi
      echo "info: Installing Xray $INSTALL_VERSION for $(uname -m)"
    fi
    install_software 'curl' 'curl'
    install_software 'unzip' 'unzip'
    download_xray
    if [[ "$?" -eq '1' ]]; then
      "rm" -r "$TMP_DIRECTORY"
      echo "removed: $TMP_DIRECTORY"
      exit 1
    fi
    decompression "$ZIP_FILE"
  fi

  install_xray
  echo 'installed: /usr/local/bin/xray'
  
  "rm" -r "$TMP_DIRECTORY"
  echo "removed: $TMP_DIRECTORY"
  get_current_version
  echo "info: Xray $CURRENT_VERSION is installed."
  echo "You may need to execute a command to remove dependent software: $PACKAGE_MANAGEMENT_REMOVE curl unzip"
}

main "$@"
