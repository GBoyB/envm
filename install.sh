#!/bin/bash

set -e

{ # this ensures the entire script is downloaded #

envm_has() {
  type "$1" > /dev/null 2>&1
}

if [ -z "$ENVM_DIR" ]; then
  ENVM_DIR="$HOME/.envm"
fi

#
# Outputs the location to NVM depending on:
# * The availability of $NVM_SOURCE
# * The method used ("script" or "git" in the script, defaults to "git")
#
envm_source() {
  local NVM_METHOD
  NVM_METHOD="$1"
  local NVM_SOURCE_URL
  NVM_SOURCE_URL="$NVM_SOURCE"
  if [ -z "$NVM_SOURCE_URL" ]; then
    if [ "_$NVM_METHOD" = "_script" ]; then
      NVM_SOURCE_URL="http://github.hzspeed.cn/envm/envm.sh"
    elif [ "_$NVM_METHOD" = "_git" ] || [ -z "$NVM_METHOD" ]; then
      NVM_SOURCE_URL="https://github.com/easynode/envm.git"
    else
      echo >&2 "Unexpected value \"$NVM_METHOD\" for \$NVM_METHOD"
      return 1
    fi
  fi
  echo "$NVM_SOURCE_URL"
}

envm_download() {
  if envm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | command sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    wget $ARGS
  elif envm_has "curl"; then
    curl -q $*
  fi
}

install_envm_from_git() {
  if [ -d "$ENVM_DIR/.git" ]; then
    echo "=> envm is already installed in $ENVM_DIR, trying to update using git"
    printf "\r=> "
    cd "$ENVM_DIR" && (command git pull 2> /dev/null || {
      echo >&2 "Failed to update envm, run 'git pull' in $ENVM_DIR yourself." && exit 1
    })
  else
    # Cloning to $ENVM_DIR
    echo "=> Downloading envm from git to '$ENVM_DIR'"
    printf "\r=> "
    mkdir -p "$ENVM_DIR"
    command git clone "$(envm_source git)" "$ENVM_DIR"
  fi
  cd "$ENVM_DIR" && command git checkout --quiet master
  return
}

install_envm_as_script() {
  local NVM_SOURCE_LOCAL
  NVM_SOURCE_LOCAL=$(envm_source script)

  # Downloading to $ENVM_DIR
  mkdir -p "$ENVM_DIR"

  if [ -d "$ENVM_DIR/Envm.sh" ]; then
    echo "=> envm is already installed in $ENVM_DIR, trying to update the script"
  else
    echo "=> Downloading envm as script to '$ENVM_DIR'"
  fi
  envm_download -s --no-check-certificate "$NVM_SOURCE_LOCAL" -o "$ENVM_DIR/envm.sh" || {
    echo >&2 "Failed to download '$NVM_SOURCE_LOCAL'"
    return 1
  }
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
envm_detect_profile() {
  if [ -f "$PROFILE" ]; then
    echo "$PROFILE"
  elif [ -f "$HOME/.bashrc" ]; then
    echo "$HOME/.bashrc"
  elif [ -f "$HOME/.bash_profile" ]; then
    echo "$HOME/.bash_profile"
  elif [ -f "$HOME/.zshrc" ]; then
    echo "$HOME/.zshrc"
  elif [ -f "$HOME/.profile" ]; then
    echo "$HOME/.profile"
  fi
}

#
# Check whether the user has any globally-installed npm modules in their system
# Node, and warn them if so.
#
envm_check_global_modules() {
  command -v npm >/dev/null 2>&1 || return 0

  local NPM_VERSION
  NPM_VERSION="$(npm --version)"
  NPM_VERSION="${NPM_VERSION:--1}"
  [ "${NPM_VERSION%%[!-0-9]*}" -gt 0 ] || return 0

  local NPM_GLOBAL_MODULES
  NPM_GLOBAL_MODULES="$(
    npm list -g --depth=0 |
    sed '/ npm@/d' |
    sed '/ (empty)$/d'
  )"

  local MODULE_COUNT
  MODULE_COUNT="$(
    printf %s\\n "$NPM_GLOBAL_MODULES" |
    sed -ne '1!p' |                             # Remove the first line
    wc -l | tr -d ' '                           # Count entries
  )"

  if [ $MODULE_COUNT -ne 0 ]; then
    cat <<-'END_MESSAGE'
	=> You currently have modules installed globally with `npm`. These will no
	=> longer be linked to the active version of Node when you install a new node
	=> with `nvm`; and they may (depending on how you construct your `$PATH`)
	=> override the binaries of modules installed with `nvm`:

	END_MESSAGE
    printf %s\\n "$NPM_GLOBAL_MODULES"
    cat <<-'END_MESSAGE'

	=> If you wish to uninstall them at a later point (or re-install them under your
	=> `nvm` Nodes), you can remove them from the system Node as follows:

	     $ envm use system
	     $ npm uninstall -g a_module

	END_MESSAGE
  fi
}

envm_do_install() {
  if [ -z "$METHOD" ]; then
    # Autodetect install method
    if envm_has "git"; then
      install_envm_from_git
    elif envm_has "envm_download"; then
      install_envm_as_script
    else
      echo >&2 "You need git, curl, or wget to install envm"
      exit 1
    fi
  elif [ "~$METHOD" = "~git" ]; then
    if ! envm_has "git"; then
      echo >&2 "You need git to install envm"
      exit 1
    fi
    install_envm_from_git
  elif [ "~$METHOD" = "~script" ]; then
    if ! envm_has "envm_download"; then
      echo >&2 "You need curl or wget to install envm"
      exit 1
    fi
    install_envm_as_script
  fi

  echo

  local NVM_PROFILE
  NVM_PROFILE=$(envm_detect_profile)

  SOURCE_STR="\nexport ENVM_DIR=\"$ENVM_DIR\"\n[ -s \"\$ENVM_DIR/envm.sh\" ] && . \"\$ENVM_DIR/envm.sh\"  # This loads nvm"

  if [ -z "$NVM_PROFILE" ] ; then
    echo "=> Profile not found. Tried $NVM_PROFILE (as defined in \$PROFILE), ~/.bashrc, ~/.bash_profile, ~/.zshrc, and ~/.profile."
    echo "=> Create one of them and run this script again"
    echo "=> Create it (touch $NVM_PROFILE) and run this script again"
    echo "   OR"
    echo "=> Append the following lines to the correct file yourself:"
    printf "$SOURCE_STR"
    echo
  else
    if ! grep -qc '$ENVM_DIR' "$NVM_PROFILE"; then
      echo "=> Appending source string to $NVM_PROFILE"
      printf "$SOURCE_STR\n" >> "$NVM_PROFILE"
    else
      echo "=> Source string already in $NVM_PROFILE"
    fi
  fi
  #envm_check_global_modules
  echo "=> Try source $NVM_PROFILE to start using envm"

  envm_reset
}

#
# Unsets the various functions defined
# during the execution of the install script
#
envm_reset() {
  unset -f envm_reset envm_has \
    envm_source envm_download install_envm_as_script install_envm_from_git \
    envm_detect_profile envm_check_global_modules envm_do_install
}

envm_do_install

} # this ensures the entire script is downloaded #
