#!/bin/bash

# OTAWA+Patmos build script, inspired by:
# https://github.com/t-crest/patmos-misc/blob/master/build.sh

# Path containing the otawa related hg repositories
ROOT_DIR=$(pwd)

INSTALL_DIR="$ROOT_DIR/local"

PATMOS_SOURCE_PATH="$ROOT_DIR/patmos"

# Path to lp_solve
LPSOLVE_BIN=/usr/bin/lp_solve
LPSOLVE_INC=/usr/include/lpsolve
LPSOLVE_LIB=/usr/lib64/liblpsolve55.so.0


### Internal build script start
# Options from command line
DO_RECONFIGURE=false
DRYRUN=false
VERBOSE=false
ALLTARGETS="deps otawa patmos ppc2"

#
# Note: This function is only safe to use when the path exists.
# When using for build paths, make sure it has been created first.
#
function abspath() {
    local path=$1
    local pwd_restore="$(pwd)"

    # readlink -f does not work on OSX, so we do this manually
    local dir=$(dirname "$path")
    if [ -d "$dir" ]; then
	cd "$dir" > /dev/null
	path=$(basename "$path")
	# follow chain of symlinks
	while [ -L "$path" ]; do
	    path=$(readlink "$path")
	    cd $(dirname "$path") > /dev/null
	    path=$(basename "$path")
	done
	echo "$(pwd -P)/$path"
	cd "$pwd_restore" > /dev/null
    elif [[ "$BUILDDIR_SUFFIX" =~ ^/ ]]; then
	echo $path
    else
	echo "Trying to resolve non-existent relative path $path, don't want to use PWD."
	exit 1
    fi
}

function usage() {
  cat <<EOT
  Usage: $0 [-dvh] [-i <install_dir>] <targets>

    -d		Dryrun, just show what would be executed
    -h		Show this help
    -i <dir>	Set the install dir
    -r		Rerun cmake configure
    -v		Show command that are executed

  Build targets are:
    $ALLTARGETS

  * 'deps' are gliss, elm and gel, always built together.
  * ppc2 is there as a test architecture.
EOT
}

function find_bins() {
  for i in $*; do
    which $i > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
      echo "error: required program not found: $i";
      exit 1;
    fi
  done;
}

run() {
    if [ "$VERBOSE" == "true" ]; then
        echo "$@"
    fi
    if [ "$DRYRUN" != "true" ]; then
        eval $@
        ret=$?
        if [ $ret != 0 ]; then
            echo "$@ failed ($ret)!"
            exit $ret
        fi
    fi
}

should_build_target() {
	rex="(^|\s)$1($|\s)"

	if [[ $BUILD_TARGETS =~ $rex ]]; then
		return 0
	else
		return 1
	fi
}

do_install() {
	echo "** $SELF: Installing $1"
	run make install
}

while getopts ":dvhi:r" opt; do
  case $opt in
    d) DRYRUN=true; VERBOSE=true ;;
    h) usage; exit 0 ;;
    i) INSTALL_DIR="$(abspath $OPTARG)" ;;
    r) DO_RECONFIGURE=true ;;
    v) VERBOSE=true ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

SELF=`basename $0`

if [ -z $@ ]; then
	BUILD_TARGETS=$ALLTARGETS
	echo "** Building all targets by default: $BUILD_TARGETS"
else
	BUILD_TARGETS=$@
	echo "** Building targets: $BUILD_TARGETS"
fi

# check if required programs are installed.
find_bins ocamllex ocamlyacc ocamlc

# build gliss2
if should_build_target deps; then
	run pushd gliss2 ">/dev/null"
	run make
	run popd ">/dev/null"
fi

# build an architecture (just for kicks)
if should_build_target ppc2; then
	for arch in ppc2; do
		run pushd "$arch" ">/dev/null"
		run make WITH_DYNLIB=1
		run popd ">/dev/null"
	done
fi

# build other deps: elm, gel
if should_build_target deps; then
	for tool in elm gel; do
		run pushd "$tool" ">/dev/null"
		if [ ! -e CMakeCache.txt -o $DO_RECONFIGURE == true ]; then
			run cmake -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR
		else
			echo "** $SELF: $tool already configured"
		fi
		run make
		do_install $tool
		run popd ">/dev/null"
	done
fi

# otawa itself
if should_build_target otawa; then
	run pushd otawa ">/dev/null"
		if [ ! -e CMakeCache.txt -o $DO_RECONFIGURE == true ]; then
			run cmake -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR -DLP_SOLVE5=$LPSOLVE_BIN -DLP_SOLVE5_INCLUDE=$LPSOLVE_INC -DLP_SOLVE5_LIB=$LPSOLVE_LIB
		else
			echo "** $SELF: OTAWA already configured"
		fi
		run make
		do_install otawa
	run popd ">/dev/null"
fi

if should_build_target patmos; then
	# patmos arch
	run pushd "$PATMOS_SOURCE_PATH/patmos" ">/dev/null"
	run make WITH_DYNLIB=1 GLISS_PREFIX=$ROOT_DIR/gliss2
	run popd ">/dev/null"

	# patmos modules
	BUILD_PATH=$ROOT_DIR/patmos/build
	for module in otawa-patmos patmos-wcet; do
		DIR=$BUILD_PATH/$module
		run mkdir -p $DIR
		run pushd "$DIR" ">/dev/null"
		run cmake --no-warn-unused-cli -DOTAWA_CONFIG=$INSTALL_DIR/bin/otawa-config -DGLISS_PATH=$ROOT_DIR/gliss2 $PATMOS_SOURCE_PATH/$module
		run make
		run make install
		run popd ">/dev/null"
	done
fi
