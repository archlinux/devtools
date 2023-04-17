#!/bin/bash

# NOTE: This requires GNU getopt
if ! ARGS=$(getopt --options vdm:D: \
		--long verbose,debug,memory:,debugfile: \
		--name 'pkgctl foo' -- "$@"); then
	exit 1
fi

eval set -- "$ARGS"

echo "${ARGS}"

while (( $# )); do
  case "$1" in
    -v | --verbose ) echo verbose; shift ;;
    -d | --debug ) echo debug; shift ;;
    -m | --memory ) echo "memory=$2"; shift 2 ;;
    -D | --debugfile ) echo "debugfile=$2"; shift 2 ;;
	--)
		echo --
		shift
		break
		;;
	-*)
		echo "invalid argument: %s" "$1"
		exit 1
		;;
	*)
		echo STAR "$1"
		shift
		;;
  esac
done

echo main

if (( ! $# )); then
	echo missing positional param: version
	exit 1
fi
version=$1
shift

echo "version $version"
echo "$@"
