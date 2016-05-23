# Easy Node Version Manager
# Implemented as a POSIX-compliant function
# Should work on sh, dash, bash, ksh, zsh
# To use source this file from your bash profile


{ # this ensures the entire script is downloaded #

NVM_SCRIPT_SOURCE="$_"

MIRROR_NODE="http://github.hzspeed.cn/mirrors/node"
MIRROR_IOJS="http://github.hzspeed.cn/mirrors/iojs"
MIRROR_ALINODE="http://github.hzspeed.cn/dist/alinode-node"
MIRROR_EASYNODE="http://github.hzspeed.cn/dist/easynode"
MIRROR_PROFILER="http://github.hzspeed.cn/dist/node-profiler"

ENVM_IFS='-' #TODO

_envm_has() {
  type "$1" > /dev/null 2>&1
}

_envm_is_alias() {
  # this is intentionally not "command alias" so it works in zsh.
  \alias "$1" > /dev/null 2>&1
}

_envm_download() {
  if _envm_has "curl"; then
    curl -q $*
  elif _envm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | command sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    eval wget $ARGS
  fi
}

_envm_has_system_node() {
  [ "$(envm deactivate >/dev/null 2>&1 && command -v node)" != '' ]
}

_envm_has_system_iojs() {
  [ "$(envm deactivate >/dev/null 2>&1 && command -v iojs)" != '' ]
}

_envm_print_npm_version() {
  if _envm_has "npm"; then
    npm --version 2>/dev/null | command xargs printf " (npm v%s)"
  fi
}

# Make zsh glob matching behave same as bash
# This fixes the "zsh: no matches found" errors
if _envm_has "unsetopt"; then
  unsetopt nomatch 2>/dev/null
  NVM_CD_FLAGS="-q"
fi

# Auto detect the ENVM_DIR when not set
if [ -z "$ENVM_DIR" ]; then
  if [ -n "$BASH_SOURCE" ]; then
    NVM_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
  export ENVM_DIR=$(cd $NVM_CD_FLAGS $(dirname "${NVM_SCRIPT_SOURCE:-$0}") > /dev/null && \pwd)
fi
unset NVM_SCRIPT_SOURCE 2> /dev/null


_envm_tree_contains_path() {
  local tree
  tree="$1"
  local node_path
  node_path="$2"

  if [ "@$tree@" = "@@" ] || [ "@$node_path@" = "@@" ]; then
    >&2 echo "both the tree and the node path are required"
    return 2
  fi

  local pathdir
  pathdir=$(dirname "$node_path")
  while [ "$pathdir" != "" ] && [ "$pathdir" != "." ] && [ "$pathdir" != "/" ] && [ "$pathdir" != "$tree" ]; do
    pathdir=$(dirname "$pathdir")
  done
  [ "$pathdir" = "$tree" ]
}

_envm_rc_version() {
  export ENVM_RC_VERSION=''
  local NVMRC_PATH
  NVMRC_PATH="$ENVM_DIR/.envmrc"
  if [ -e "$NVMRC_PATH" ]; then
    read ENVM_RC_VERSION < "$NVMRC_PATH"
    echo "Found '$NVMRC_PATH' with version <$NVM_RC_VERSION>"
  else
    >&2 echo "No .envmrc file found"
    return 1
  fi
}

_envm_version_greater() {
  local LHS
  LHS=$(_envm_normalize_version "$1")
  local RHS
  RHS=$(_envm_normalize_version "$2")
  [ $LHS -gt $RHS ];
}

_envm_version_greater_than_or_equal_to() {
  local LHS
  LHS=$(_envm_normalize_version "$1")
  local RHS
  RHS=$(_envm_normalize_version "$2")
  [ $LHS -ge $RHS ];
}

_envm_version_dir() {
  local PREFIX
  PREFIX="$(_envm_get_prefix $1)"
  echo "$ENVM_DIR/versions/$PREFIX"
}

# ~/versions/node/v0.12.4 etc
_envm_version_path() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo "version is required" >&2
    return 3
  fi
  echo "$(_envm_version_dir $VERSION)/$(_envm_get_version $VERSION)"
}


_envm_ensure_version_installed() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="$1"
  local LOCAL_VERSION
  LOCAL_VERSION="$(_envm_version "$PROVIDED_VERSION")"
  local NVM_VERSION_DIR
  NVM_VERSION_DIR="$(_envm_version_path "$LOCAL_VERSION")"
  if [ ! -d "$NVM_VERSION_DIR" ]; then
    echo "N/A: version \"$PROVIDED_VERSION\" is not yet installed" >&2
    return 1
  fi
}


# Expand a version using the version cache
_envm_version() {
  local PATTERN
  PATTERN=$1
  local VERSION
  # The default version is the current one
  if [ -z "$PATTERN" ]; then
    PATTERN='current'
  fi

  if [ "$PATTERN" = "current" ]; then
    _envm_ls_current
    return $?
  fi

  VERSION="$(_envm_ls "$PATTERN" | tail -n1)"
  if [ -z "$VERSION" ] || [ "_$VERSION" = "_N/A" ]; then
    echo "N/A"
    return 3;
  else
    echo "$VERSION"
  fi
}


_envm_remote_version() {
  local PREFIX
  PREFIX="$(_envm_get_prefix "$1")"
  local PATTERN
  PATTERN="$(_envm_get_version "$1")"
  local VERSION
  VERSION="$(_envm_remote_versions "$PREFIX" | command grep -w "$PATTERN")"
  if [ "_$VERSION" = '_N/A' ] || [ -z "$VERSION" ] ; then
    echo "N/A"
    return 3
  fi
  echo "$VERSION"
}


_envm_remote_versions() {
  local PATTERN
  PATTERN="$1"
  VERSIONS="$(_envm_ls_remote $PATTERN)"

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  else
    echo "$VERSIONS"
  fi
}


_envm_normalize_version() {
  echo "${1#v}" | command awk -F. '{ printf("%d%06d%06d\n", $1,$2,$3); }'
}


_envm_format_version() {
  local VERSION
  VERSION="$1"
  if [ "_$(_envm_num_version_groups "$VERSION")" != "_3" ]; then
    _envm_format_version "${VERSION%.}.0"
  else
    echo "$VERSION"
  fi
}


_envm_num_version_groups() {
  local VERSION
  VERSION="$1"
  VERSION="${VERSION#v}"
  VERSION="${VERSION%.}"
  if [ -z "$VERSION" ]; then
    echo "0"
    return
  fi
  local NVM_NUM_DOTS
  NVM_NUM_DOTS=$(echo "$VERSION" | command sed -e 's/[^\.]//g')
  local NVM_NUM_GROUPS
  NVM_NUM_GROUPS=".$NVM_NUM_DOTS" # add extra dot, since it's (n - 1) dots at this point
  echo "${#NVM_NUM_GROUPS}"
}


_envm_strip_path() {
  echo "$1" | command sed \
    -e "s#$ENVM_DIR/[^/]*$2[^:]*:##g" \
    -e "s#:$ENVM_DIR/[^/]*$2[^:]*##g" \
    -e "s#$ENVM_DIR/[^/]*$2[^:]*##g" \
    -e "s#$ENVM_DIR/versions/[^/]*/[^/]*$2[^:]*:##g" \
    -e "s#:$ENVM_DIR/versions/[^/]*/[^/]*$2[^:]*##g" \
    -e "s#$ENVM_DIR/versions/[^/]*/[^/]*$2[^:]*##g"
}

_envm_prepend_path() {
  if [ -z "$1" ]; then
    echo "$2"
  else
    echo "$2:$1"
  fi
}

_envm_binary_available() {
  # binaries started with node 0.11.12
  local FIRST_VERSION_WITH_BINARY
  FIRST_VERSION_WITH_BINARY="0.3.1"
  _envm_version_greater_than_or_equal_to "$(_envm_get_version $1)" "$FIRST_VERSION_WITH_BINARY"
}

_envm_ls_current() {
  local NVM_LS_CURRENT_NODE_PATH
  NVM_LS_CURRENT_NODE_PATH="$(command which node 2> /dev/null)"
  if [ $? -ne 0 ]; then
    echo 'none'
  elif _envm_tree_contains_path "$(_envm_version_dir iojs-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(iojs $(iojs -v 2>/dev/null))"
  elif _envm_tree_contains_path "$(_envm_version_dir node-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(node $(node -v 2>/dev/null))"
  elif _envm_tree_contains_path "$(_envm_version_dir alinode-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(alinode-$(node -p 'process.alinode' 2>/dev/null)) --> (node-$(node -v 2>/dev/null))"
  elif _envm_tree_contains_path "$(_envm_version_dir easynode-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(easynode-$(node -p 'process.easynode' 2>/dev/null)) --> (node-$(node -v 2>/dev/null))"
  elif _envm_tree_contains_path "$(_envm_version_dir profiler-v)" "$NVM_LS_CURRENT_NODE_PATH"; then
    echo "(profiler $(node -v 2>/dev/null))"
  else
    echo 'system'
  fi
}


_envm_alinode_prefix() {
  echo "alinode"
}

_envm_easynode_prefix() {
  echo "easynode"
}


_envm_iojs_prefix() {
  echo "iojs"
}

_envm_node_prefix() {
  echo "node"
}

_envm_get_prefix() {
  echo "${1%-*}"
}

_envm_get_version() {
  echo "${1#*-}"
}

# 访问本地
_envm_ls() {
  local PATTERN
  PATTERN=$1
  local BASE_VERSIONS_DIR
  BASE_VERSIONS_DIR="$ENVM_DIR/versions"
  if [ ! -d "$BASE_VERSIONS_DIR" ]; then
    mkdir "$BASE_VERSIONS_DIR"
  fi
  find $BASE_VERSIONS_DIR -maxdepth 2 -type d \
    | sed 's|'$BASE_VERSIONS_DIR'/||g' \
    | egrep "/v[0-9]+\.[0-9]+\.[0-9]+" \
    | sort -t. -u -k 1 -k 2,2n -k 3,3n \
    | sed 's|/|-|g' \
    | command grep -w "${PATTERN}"

}

_envm_lookup_nodemap() {
  local PATTERN
  PATTERN="$1"
  local NODEMAP
  local mirror
  case "$PATTERN" in
    "alinode") mirror=$MIRROR_ALINODE
    ;;
    "easynode") mirror=$MIRROR_EASYNODE
    ;;
    "profiler") mirror=$MIRROR_PROFILER
    ;;
    *) return 1
    ;;
  esac

  NODEMAP="$(_envm_download -L -s "$mirror/index.tab" -o - \
    | command sed "
        1d;
        s/^/$PATTERN-/;" \
    | command awk '{ print "Node.js upkeep release to provide "$1 " with Node.js " $10}' \
    | command grep -w "$PATTERN" \
    | command sort)"

  if [ -z "$NODEMAP" ]; then
    return 3
  fi
  echo "$NODEMAP"
}

_envm_ls_remote() {
  local PATTERN
  PATTERN="$1"
  local VERSIONS
  local mirror
  case "$PATTERN" in
    "node") mirror=$MIRROR_NODE ;;
    "iojs") mirror=$MIRROR_IOJS ;;
    "alinode") mirror=$MIRROR_ALINODE ;;
    "easynode") mirror=$MIRROR_EASYNODE ;;
    "profiler") mirror=$MIRROR_PROFILER ;;
  esac

  VERSIONS="$(_envm_download -L -s "$mirror/index.tab" -o - \
    | command sed "
        1d;
        s/^/$PATTERN-/;
        s/[[:blank:]].*//" \
    | command grep -w "$PATTERN" \
    | command sort)"

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi
  echo "$VERSIONS"
}


_envm_checksum() {
  local NVM_CHECKSUM
  if _envm_has "sha256sum" && ! _envm_is_alias "sha256sum"; then
    NVM_CHECKSUM="$(command sha256sum "$1" | command awk '{print $1}')"
  elif _envm_has "shasum" && ! _envm_is_alias "shasum"; then
    NVM_CHECKSUM="$(command shasum -a 256 "$1" | command awk '{print $1}')"
  else
    echo "Unaliased sha256sum, or shasum not found." >&2
    return 2
  fi

  if [ "_$NVM_CHECKSUM" = "_$2" ]; then
    return
  elif [ -z "$2" ]; then
    echo 'Checksums empty' #missing in raspberry pi binary
    return
  else
    echo 'Checksums do not match.' >&2
    return 1
  fi
}

_envm_print_versions() {
  local VERSION
  local FORMAT
  local NVM_CURRENT
  NVM_CURRENT=$(_envm_ls_current)
  echo "$1" | while read VERSION; do
    if [ "_$VERSION" = "_$NVM_CURRENT" ]; then
      FORMAT='\033[0;32m-> %12s\033[0m'
    elif [ "$VERSION" = "system" ]; then
      FORMAT='\033[0;33m%15s\033[0m'
    elif [ -d "$(_envm_version_path "$VERSION" 2> /dev/null)" ]; then
      FORMAT='\033[0;34m%15s\033[0m'
    else
      FORMAT='%15s'
    fi
    printf "$FORMAT\n" $VERSION
  done
}


_envm_get_os() {
  local NVM_UNAME
  NVM_UNAME="$(uname -a)"
  local NVM_OS
  case "$NVM_UNAME" in
    Linux\ *) NVM_OS=linux ;;
    Darwin\ *) NVM_OS=darwin ;;
    SunOS\ *) NVM_OS=sunos ;;
    FreeBSD\ *) NVM_OS=freebsd ;;
  esac
  echo "$NVM_OS"
}

_envm_get_arch() {
  local NVM_UNAME
  NVM_UNAME="$(uname -m)"
  local NVM_ARCH
  case "$NVM_UNAME" in
    x86_64) NVM_ARCH="x64" ;;
    i*86) NVM_ARCH="x86" ;;
    *) NVM_ARCH="$NVM_UNAME" ;;
  esac
  echo "$NVM_ARCH"
}


_envm_install_binary() {
  local PREFIXED_VERSION
  PREFIXED_VERSION="$1"

  local VERSION
  VERSION="$(_envm_get_version "$PREFIXED_VERSION")" #v0.12.4
  local PREFIX
  PREFIX="$(_envm_get_prefix "$PREFIXED_VERSION")" #node, iojs, alinode, easynode


  local VERSION_PATH
  VERSION_PATH="$(_envm_version_path "$PREFIXED_VERSION")"
  local NVM_OS
  NVM_OS="$(_envm_get_os)"
  local t
  local url
  local sum
  local mirror

  case "$PREFIX" in
    "node") mirror=$MIRROR_NODE ;;
    "iojs") mirror=$MIRROR_IOJS ;;
    "alinode") mirror=$MIRROR_ALINODE ;;
    "easynode") mirror=$MIRROR_EASYNODE ;;
    "profiler") mirror=$MIRROR_PROFILER ;;
  esac

  if [ -n "$NVM_OS" ]; then
    if _envm_binary_available "$VERSION"; then
      t="$VERSION-$NVM_OS-$(_envm_get_arch)"
      url="$mirror/$VERSION/$PREFIX-${t}.tar.gz"
      sum="$(_envm_download -L -s $mirror/$VERSION/SHASUMS256.txt -o - \
           | command grep $PREFIX-${t}.tar.gz | command awk '{print $1}')"
      if [ -z "$sum" ]; then
        echo >&2 "Binary download failed, $PREFIX-${t}.tar.gz N/A." >&2
        return 2
      fi
      local tmpdir
      tmpdir="$ENVM_DIR/bin/$PREFIX-${t}"
      local tmptarball
      tmptarball="$tmpdir/$PREFIX-${t}.tar.gz"
      local NVM_INSTALL_ERRORED
      command mkdir -p "$tmpdir" && \
        _envm_download -L -C - --progress-bar $url -o "$tmptarball" || \
        NVM_INSTALL_ERRORED=true
      if grep '404 Not Found' "$tmptarball" >/dev/null; then
        NVM_INSTALL_ERRORED=true
        echo >&2 "HTTP 404 at URL $url";
      fi
      if (
        [ "$NVM_INSTALL_ERRORED" != true ] && \
        _envm_checksum "$tmptarball" $sum && \
        command tar -xzf "$tmptarball" -C "$tmpdir" --strip-components 1 && \
        command rm -f "$tmptarball" && \
        command mkdir -p "$VERSION_PATH" && \
        command mv "$tmpdir"/* "$VERSION_PATH"
      ); then
        return 0
      else
        echo >&2 "Binary download failed, trying source." >&2
        command rm -rf "$tmptarball" "$tmpdir"
        return 1
      fi
    fi
  fi
  return 2
}

_envm_self_upgrade() {
  command wget --tries=3 --timeout=15 -O- http://github.hzspeed.cn/envm/envm.sh \
  | command bash 2>/dev/null
}

_envm_check_params() {
  if [ "_$1" = '_system' ]; then
    return
  fi
  echo "$1" | egrep -o '^[a-z]+-v[0-9]+\.[0-9]+\.[0-9]+$' > /dev/null
}

envm() {
  if [ $# -lt 1 ]; then
    envm help
    return
  fi

  local GREP_OPTIONS
  GREP_OPTIONS=''

  # initialize local variables
  local VERSION

  case $1 in
    "help" )
      echo
      echo "Easy Node Version Manager"
      echo
      echo "Usage:"
      echo "  envm help                                       Show this message"
      echo "  envm -v                                         Print out the latest released version of envm"
      echo "  envm lookup                                     Print easynode base on node versions"
      echo "  envm install <version>                          Download and install a <version>"
      echo "  envm uninstall <version>                        Uninstall a version"
      echo "  envm use <version>                              Modify PATH to use <version>. Uses .envmrc if available"
      echo "  envm current                                    Display currently activated version"
      echo "  envm ls [node|alinode|easynode|iojs|profiler]   List versions matching a given description"
      echo "  envm ls-remote [node|alinode|easynode|iojs|profiler]     List remote versions available for install"
      echo "  envm upgrade                                    Upgrade \`envm\` self"
      echo "  envm unload                                     Unload \`envm\` from shell"

      echo
      echo "Example:"
      echo "  envm install easynode-v1.0.0           Install a specific version number"
      echo "  envm use easynode-v1.0.0               Use the latest available release"
      echo
      echo "Note:"
      echo "  to remove, delete, or uninstall envm - just remove ~/.envm, ~/.npm, and ~/.bower folders"
      echo
    ;;

    "install" | "i" )
      local nobinary
      local version_not_provided
      version_not_provided=0
      local provided_version
      local NVM_OS
      NVM_OS="$(_envm_get_os)"

      if ! _envm_has "curl" && ! _envm_has "wget"; then
        echo 'nvm needs curl or wget to proceed.' >&2;
        return 1
      fi

      if [ $# -lt 2 ]; then
        version_not_provided=1
        >&2 envm help
        return 127
      fi

      shift

      nobinary=0
      provided_version="$1"
      if ! _envm_check_params "$1" ; then
        echo "Version '$1' not vaild." >&2
        return 3
      fi
      VERSION="$(_envm_remote_version "$provided_version")"

      if [ "_$VERSION" = "_N/A" ]; then
        echo "Version '$provided_version' not found - try \`envm ls-remote\` to browse available versions." >&2
        echo "Or try \`envm lookup\` for details." >&2
        return 3
      fi
      echo $VERSION
      local VERSION_PATH
      VERSION_PATH="$(_envm_version_path "$VERSION")"
      if [ -d "$VERSION_PATH" ]; then
        echo "$VERSION is already installed." >&2
        return $?
      fi

      if [ "_$NVM_OS" = "_freebsd" ] || [ "_$NVM_OS" = "_sunos" ]; then
        # node.js and io.js do not have a FreeBSD binary
        nobinary=1
      fi
      local NVM_INSTALL_SUCCESS
      # skip binary install if "nobinary" option specified.
      if [ $nobinary -ne 1 ] && _envm_binary_available "$VERSION"; then
        if _envm_install_binary "$VERSION"; then
          NVM_INSTALL_SUCCESS=true
        fi
      fi
      if [ "$NVM_INSTALL_SUCCESS" != true ]; then
         echo "Installing binary from source is not currently supported" >&2
         return 105
      fi
      return $?
    ;;
    "uninstall" )
      if [ $# -ne 2 ]; then
        >&2 envm help
        return 127
      fi

      local PATTERN
      PATTERN="$2"

      if ! _envm_check_params "$2" ; then
        echo "Version '$2' not vaild." >&2
        return 3
      fi

      VERSION="$(_envm_version "$PATTERN")"
      if [ "_$VERSION" = "_$(_envm_ls_current)" ]; then
        echo "envm: Cannot uninstall currently-active node version, $VERSION (inferred from $PATTERN)." >&2
        return 1
      fi

      local VERSION_PATH
      VERSION_PATH="$(_envm_version_path "$VERSION")"
      if [ ! -d "$VERSION_PATH" ]; then
        echo "$VERSION version is not installed..." >&2
        return;
      fi

      t="$VERSION-$(_envm_get_os)-$(_envm_get_arch)"

      local NVM_PREFIX
      local NVM_SUCCESS_MSG

      NVM_PREFIX="$(_envm_get_prefix)"
      NVM_SUCCESS_MSG="Uninstalled  $VERSION and reopen your terminal."

      # Delete all files related to target version.
      command rm -rf "$ENVM_DIR/src/$NVM_PREFIX-$VERSION" \
             "$ENVM_DIR/src/$NVM_PREFIX-$VERSION.tar.gz" \
             "$ENVM_DIR/bin/$NVM_PREFIX-${t}" \
             "$ENVM_DIR/bin/$NVM_PREFIX-${t}.tar.gz" \
             "$VERSION_PATH" 2>/dev/null
      echo "$NVM_SUCCESS_MSG"
    ;;
    "deactivate" )
      local NEWPATH
      NEWPATH="$(_envm_strip_path "$PATH" "/bin")"
      if [ "_$PATH" = "_$NEWPATH" ]; then
        echo "Could not find $ENVM_DIR/*/bin in \$PATH" >&2
      else
        export PATH="$NEWPATH"
        hash -r
        echo "$ENVM_DIR/*/bin removed from \$PATH"
      fi

      NEWPATH="$(_envm_strip_path "$MANPATH" "/share/man")"
      if [ "_$MANPATH" = "_$NEWPATH" ]; then
        echo "Could not find $ENVM_DIR/*/share/man in \$MANPATH" >&2
      else
        export MANPATH="$NEWPATH"
        echo "$ENVM_DIR/*/share/man removed from \$MANPATH"
      fi

      NEWPATH="$(_envm_strip_path "$NODE_PATH" "/lib/node_modules")"
      if [ "_$NODE_PATH" != "_$NEWPATH" ]; then
        export NODE_PATH="$NEWPATH"
        echo "$ENVM_DIR/*/lib/node_modules removed from \$NODE_PATH"
      fi
    ;;
    "use" )
      local PROVIDED_VERSION
      if [ $# -eq 1 ]; then
        >&2 envm help
        return 127
      else
        PROVIDED_VERSION="$2"
        VERSION="$PROVIDED_VERSION"
      fi
      if ! _envm_check_params "$2" ; then
        echo "Version '$2' not vaild." >&2
        return 3
      fi
      if [ -z "$VERSION" ]; then
        >&2 envm help
        return 127
      fi

      if [ "_$VERSION" = '_system' ]; then
        if _envm_has_system_node && envm deactivate >/dev/null 2>&1; then
          echo "Now using system version of node: $(node -v 2>/dev/null)$(_envm_print_npm_version)"
          return
        elif _envm_has_system_iojs && envm deactivate >/dev/null 2>&1; then
          echo "Now using system version of io.js: $(iojs --version 2>/dev/null)$(_envm_print_npm_version)"
          return
        else
          echo "System version of node not found." >&2
          return 127
        fi
      elif [ "_$VERSION" = "_∞" ]; then
        echo "The alias \"$PROVIDED_VERSION\" leads to an infinite loop. Aborting." >&2
        return 8
      fi

      # This _envm_ensure_version_installed call can be a performance bottleneck
      # on shell startup. Perhaps we can optimize it away or make it faster.
      _envm_ensure_version_installed "$PROVIDED_VERSION"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" != "0" ]; then
        return $EXIT_CODE
      fi

      local NVM_VERSION_DIR
      NVM_VERSION_DIR="$(_envm_version_path "$VERSION")"

      # Strip other version from PATH
      PATH="$(_envm_strip_path "$PATH" "/bin")"
      # Prepend current version
      PATH="$(_envm_prepend_path "$PATH" "$NVM_VERSION_DIR/bin")"
      if _envm_has manpath; then
        if [ -z "$MANPATH" ]; then
          MANPATH=$(manpath)
        fi
        # Strip other version from MANPATH
        MANPATH="$(_envm_strip_path "$MANPATH" "/share/man")"
        # Prepend current version
        MANPATH="$(_envm_prepend_path "$MANPATH" "$NVM_VERSION_DIR/share/man")"
        export MANPATH
      fi
      export PATH
      hash -r
      export NVM_PATH="$NVM_VERSION_DIR/lib/node"
      export NVM_BIN="$NVM_VERSION_DIR/bin"
      echo "$VERSION" > "$ENVM_DIR/.envmrc"
      echo "$NVM_VERSION_DIR/bin" > "$HOME/.nodepath"
      echo "Now using node $VERSION$(_envm_print_npm_version)"

    ;;
    "ls" | "list" )
      local NVM_LS_OUTPUT
      local NVM_LS_EXIT_CODE
      if [ $# -ne 2 ]; then
        >&2 envm help
        return 127
      fi
      NVM_LS_OUTPUT=$(_envm_ls "$2")
      NVM_LS_EXIT_CODE=$?
      _envm_print_versions "$NVM_LS_OUTPUT"
      return $NVM_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote" )
      local PATTERN
      if [ $# -ne 2 ]; then
        >&2 envm help
        return 127
      fi
      PATTERN="$2"

      local NVM_LS_REMOTE_EXIT_CODE
      NVM_LS_REMOTE_EXIT_CODE=0
      local NVM_LS_REMOTE_OUTPUT
      NVM_LS_REMOTE_OUTPUT=$(_envm_ls_remote "$PATTERN")
      NVM_LS_REMOTE_EXIT_CODE=$?

      local NVM_OUTPUT
      NVM_OUTPUT="$(echo "$NVM_LS_REMOTE_OUTPUT" | command grep -v "N/A" | sed '/^$/d')"
      if [ -n "$NVM_OUTPUT" ]; then
        _envm_print_versions "$NVM_OUTPUT"
        return $NVM_LS_REMOTE_EXIT_CODE
      else
        _envm_print_versions "N/A"
        return 3
      fi
    ;;

    "lookup" )
     _envm_lookup_nodemap "easynode"
    ;;

    "current" )
      _envm_version current
    ;;

    "upgrade" )
      _envm_self_upgrade
      echo "then try source ~/.bashrc, or ~/.zshrc"
    ;;

    "--v" | "-v" )
      echo "v1.x"
    ;;

    "unload" )
      unset -f envm _envm_print_versions _envm_checksum \
        _envm_iojs_prefix _envm_node_prefix _envm_lookup_nodemap \
        _envm_ls_remote _envm_ls _envm_remote_version _envm_remote_versions \
        _envm_version _envm_check_params _envm_self_upgrade\
        _envm_version_greater _envm_version_greater_than_or_equal_to \
        _envm_supports_source_options > /dev/null 2>&1
      unset ENVM_DIR NVM_CD_FLAGS > /dev/null 2>&1
    ;;
    * )
      >&2 envm help
      return 127
    ;;
  esac
}


function _envm_complete() {
    local cur prev opts

    COMPREPLY=()

    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-v help install uninstall use current ls ls-remote upgrade lookup"
    option="alinode easynode node iojs profiler"

    if [[ $prev == 'envm' ]] ; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi

    case "$prev" in
    -* )
        COMPREPLY=( $( compgen -W "$opts" -- $cur ) )
        ;;
    ls | ls-remote )
        COMPREPLY=( $( compgen -W "$option" -- $cur ) )
        ;;
    esac

}

if _envm_has "complete"; then
  complete -F _envm_complete envm
fi

if _envm_rc_version >/dev/null 2>&1; then
  envm use "$ENVM_RC_VERSION" >/dev/null 2>&1
fi

} # this ensures the entire script is downloaded #


#_envm_version_dir
#_envm_ls "node"
#_envm_ls "iojs"
#_envm_remote_versions "alinode"
#_envm_remote_versions "easynode"
#_envm_remote_version "alinode-v0.12.5"
#_envm_remote_version "easynode-v7.0.0"
#_envm_remote_version "alinode-v0.12.7"
#_envm_ls "node-v0.12.4"
#_envm_version "node-v0.12.4"
#_envm_ensure_version_installed "node-v0.12.4"

# cmd test
#envm --version
#envm list-remote "iojs"
#envm ls-remote "alinode"
#envm install "node-v0.12.4"
#envm install "alinode-v0.12.4"
#envm install "iojs-v2.4.0"

#envm use "node-v0.12.4"

#envm ls "node"
#envm ls-remote
#envm install "alinode-v0.12.4"
#envm install "profiler-v0.12.6"
#envm use "profiler-v0.12.6"
#_envm_self_upgrade
#envm install "alinode-v0.3.2"
#_envm_lookup_nodemap "alinode"
#_envm_lookup_nodemap "profiler"

