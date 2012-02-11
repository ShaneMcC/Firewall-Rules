#!/bin/bash

# This shouldn't really need to be edited.
#
# rules.rules is where you want to be!

# Find out where we are and load functions.
BASEDIR=${0%/*}
if [ "${BASEDIR}" = "${0}" ]; then
	BASEDIR=`which $0 2>/dev/null`;
	BASEDIR=${BASEDIR%/*};
fi
if [ "${BASEDIR:0:1}" != "/" ]; then
	BASEDIR=${PWD}/${BASEDIR};
fi;
export IPT="echo";
if [ -e "${BASEDIR}/functions.sh" ]; then
	. ${BASEDIR}/functions.sh;
else
	echo "Unable to find functions";
	exit 1;
fi;

# Test functions.sh has loaded.
TEST=`do_test 2>/dev/null`
if [ "${TEST}" = "" ]; then
	echo "Unable to load functions";
	exit 1;
fi;

# Finally, its rule time!

if [ "${1}" = "" ]; then
	RULES="rules"
else
	RULES="${1}"
fi;

if [ -e "${BASEDIR}/${RULES}.rules" ]; then
	. ${BASEDIR}/${RULES}.rules;
else
	echo "Unable to find rules file ${RULES}.rules";
	exit 1;
fi;