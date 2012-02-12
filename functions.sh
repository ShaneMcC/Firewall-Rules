#!/bin/sh

# Used for testing rules are ok.
do_test() { echo 'OK'; }

# Set a setting!
fwset() {
	SETTING="FW_${FWMODE}_${1}"
	shift;
	if [ "${1}" = "to" -o "${1}" = "as" -o "${1}" = "=" -o "${1}" = "is" ]; then shift; fi
	VALUE=""${@}""
	if [ "${IS_FAST}" != "1" ]; then
		SETTING=`echo "${SETTING}" | sed "s/[^A-Za-z0-9_]//g"`
	fi;
	export ${SETTING}="${VALUE}"
	#VAL='export '${SETTING}'="'${VALUE}'"'
	#RES=`eval $VAL 2>&1`
}

# Set a setting as part of a type
fwsettype() {
	TYPE="${1}"
	SETTING="${2}"
	shift; shift;
	fwset "__${TYPE}__${SETTING}" "${@}"
}

# Get a setting!
fwget() {
	SETTING="FW_${FWMODE}_${1}"
	if [ "${IS_FAST}" != "1" ]; then
		SETTING=`echo "${SETTING}" | sed "s/[^A-Za-z0-9_]//g"`
	fi;
	VAL='echo "${'${SETTING}'}"'
	RES=`eval $VAL 2>&1`
	if [ "${RES}" = "" ]; then
		echo ${1}
	else
		echo ${RES}
	fi;
}

# Get a setting as part of a type
fwgettype() {
	TYPE="${1}"
	SETTING="${2}"
	shift; shift;
	RES=`fwget "__${TYPE}__${SETTING}"`
	if [ "${RES}" = "__${TYPE}__${SETTING}" ]; then
		echo ${SETTING}
	else
		echo ${RES}
	fi;
}

applyRule() {
	if [ "${IPT}" != "" ]; then
		if [ "${IS_DEBUG}" = "1" ]; then
			echo "${IPT} "${@}""
		else
			eval ${IPT} "${@}"
		fi;
	fi;
}

mode() {
	if [ "${1}" = "silent" ]; then
		if [ "${IS_SILENT}" != "1" ]; then
			export IS_SILENT="1"
		else
			export IS_SILENT="0"
		fi;
	elif [ "${1}" = "debug" ]; then
		if [ "${IS_DEBUG}" != "1" ]; then
			export IS_DEBUG="1"
		else
			export IS_DEBUG="0"
		fi;
	elif [ "${1}" = "fast" ]; then
		if [ "${IS_FAST}" != "1" ]; then
			export IS_FAST="1"
		else
			export IS_FAST="0"
		fi;
	elif [ "${1}" = "ipv6" ]; then
		export FWMODE="${1}"
		findiptbinary ip6tables
	elif [ "${1}" = "ipv4" ]; then
		export FWMODE="${1}"
		findiptbinary iptables
	elif [ "${1}" = "null" ]; then
		export FWMODE="${1}"
		export IPT=""
	fi;
}

findiptbinary() {
	BIN="${1}"

	# Find Binary.
	RES=`which s${BIN} 2>/dev/null`;
	if [ "${RES}" = "" ]; then
		RES=`which sxtables-multi 2>/dev/null`;
		if [ "${RES}" != "" ]; then
			RES="${RES} ${BIN}"
		fi;
	fi;

	if [ "${RES}" = "" ]; then
		echo "Unable to find ${BIN}" >&2
		exit 1;
	else
		export IPT=${RES}
	fi;
}


# Log a line
log() {
	if [ "${IS_SILENT}" != "1" ]; then
		if [ "${IS_DEBUG}" = "1" ]; then
			echo ""
			echo "# " "${@}"
		else
			echo "${@}"
		fi;
	fi;
}

# Ignore a rule!
ignore() { echo -n ""; }
REM() { echo -n ""; }

# Flush a chain...
flush() { empty $@; }
empty() {
	log empty "${@}"
	if [ "${1}" = '' ]; then
		applyRule "-F"
		applyRule "-X"
	else
		applyRule "-F '${1}'"
	fi;
}


# Set the policy for a chain
policy() {
	log policy "${@}"
	if [ "${1}" = "for" ]; then shift; fi
	CHAIN="${1}"
	shift;
	if [ "${1}" = "to" -o "${1}" = "as" -o "${1}" = "=" -o "${1}" = "is" ]; then shift; fi
	VALUE="${1}"

	if [ "${VALUE}" = "ALLOW" ]; then VALUE="ACCEPT"; fi
	if [ "${VALUE}" = "IGNORE" ]; then VALUE="DROP"; fi

	applyRule "-P '${CHAIN}' '${VALUE}'"
}

# Add an allow rule
allow() {
	log allow "${@}"
	addRule ACCEPT "${@}"
}

# Add a reject rule
reject() {
	log reject "${@}"
	addRule REJECT "${@}"
}

# Add a drop rule
drop() {
	log drop "${@}"
	addRule DROP "${@}"
}

# Add an ignore (drop) rule
ignore() {
	log ignore "${@}"
	addRule DROP "${@}"
}

# Check a group.
check() {
	log check "${@}"
	addRule "-" "${@}"
}


addRule() {
	ACTION="${1}"
	shift;
	if [ "${1}" = "input" -o "${1}" = "inbound" ]; then
		CHAIN="INPUT"
	elif [ "${1}" = "forward" ]; then
		CHAIN="FORWARD"
	elif [ "${1}" = "output" -o "${1}" = "outbound" ]; then
		CHAIN="OUTPUT"
	elif [ "${1}" = "all" ]; then
		shift;
		addRule ${ACTION} input "${@}"
		addRule ${ACTION} output "${@}"
		addRule ${ACTION} forward "${@}"
		return;
	else
		echo "Invalid Direction: ${1}" >&2
		exit 1;
	fi;
	shift;

	RULE=""
	PROTO=""
	CUSTOMCHAIN=""

	GROUP=""
	GROUPCHAIN=""
	CHECKCHAIN=""

	while [ -n "$*" ]; do
		############################
		## STATE
		############################
		if [ "${1}" = "state" ]; then
			shift;
			RULE=${RULE}' -m state --state "'${1}'"'

		############################
		## on [port]
		############################
		elif [ "${1}" = "on" ]; then
			shift;
			if [ "${1}" = "port" ]; then
				shift;
				if [ "${PROTO}" = "" ]; then
					PROTO="1"
					RULE=${RULE}' -p tcp'
				fi;
				RULE=${RULE}' --dport "'${1}'"'
			else
				TARGET=`fwget ${1}`
				RULE=${RULE}' -i "'${TARGET}'"'
			fi;

		############################
		## from [port]
		############################
		elif [ "${1}" = "from" ]; then
			shift;
			if [ "${1}" = "port" ]; then
				shift;
				if [ "${PROTO}" = "" ]; then
					PROTO="1"
					RULE=${RULE}' -p tcp'
				fi;
				RULE=${RULE}' --sport "'${1}'"'
			elif [ "${1}" = "interface" ]; then
				shift;
				TARGET=`fwget ${1}`
				RULE=${RULE}' -i "'${TARGET}'"'
			else
				TARGET=`fwget ${1}`
				ISHOST=`fwgettype "HOST" "${1}"`
				ISINTERFACE=`fwgettype "INTERFACE" "${1}"`
				if [ "${CUSTOMCHAIN}" = "" -a "${ISHOST}" = "1" ]; then
					CHAIN="${1}-OUT"
					CUSTOMCHAIN="1"
				elif [ "${ISINTERFACE}" = "1" ]; then
					RULE=${RULE}' -i "'${TARGET}'"'
				else
					RULE=${RULE}' -s "'${TARGET}'"'
				fi;
			fi;

		############################
		## to [port]
		############################
		elif [ "${1}" = "to" ]; then
			shift;
			if [ "${1}" = "port" ]; then
				shift;
				if [ "${PROTO}" = "" ]; then
					PROTO="1"
					RULE=${RULE}' -p tcp'
				fi;
				RULE=${RULE}' --dport "'${1}'"'
			elif [ "${1}" = "interface" ]; then
				shift;
				TARGET=`fwget ${1}`
				RULE=${RULE}' -o "'${TARGET}'"'
			else
				TARGET=`fwget ${1}`
				ISHOST=`fwgettype "HOST" "${1}"`
				ISINTERFACE=`fwgettype "INTERFACE" "${1}"`
				if [ "${CUSTOMCHAIN}" = "" -a "${ISHOST}" = "1" ]; then
					CHAIN="${1}-IN"
					CUSTOMCHAIN="1"
				elif [ "${ISINTERFACE}" = "1" ]; then
					RULE=${RULE}' -o "'${TARGET}'"'
				else
					RULE=${RULE}' -d "'${TARGET}'"'
				fi;
			fi;

		############################
		## if [group]
		############################
		elif [ "${1}" = "if" -o "${1}" = "check" -o "${1}" = "group" ]; then
			shift;
			if [ "${1}" = "group" ]; then shift; fi
			GROUP="${1}"
			if [ "${CUSTOMCHAIN}" != "" ]; then
				echo "Unable to set CHAIN to: ${CHAIN}" >&2
				exit 1;
			else
				CUSTOMCHAIN="1"
			fi;
			CHECKCHAIN="${CHAIN}"
			GROUPCHAIN="GROUP-${GROUP}"


		############################
		## proto[col]
		############################
		elif [ "${1}" = "proto" -o "${1}" = "protocol" ]; then
			shift;
			PROTO="1"
			RULE=${RULE}' -p "'${1}'"'

		############################
		## comment
		############################
		elif [ "${1}" = "comment" ]; then
			shift;
			PROTO="1"
			RULE=${RULE}' -m comment --comment "'${1}'"'

		############################
		## filler
		############################
		elif [ "${1}" = "with" ]; then
			echo -n ""
		fi;
		shift;
	done;

	if [ "${GROUPCHAIN}" != "" ]; then
		if [ "${RULE}" = "" ]; then
			checkGroupChain ${GROUP} ${CHECKCHAIN}
		else
			checkGroup ${GROUP}
			ACTION=${GROUPCHAIN}
		fi;
	fi;

	if [ "${ACTION}" != "-" ]; then
		applyRule "-A ${CHAIN} ${RULE} -j ${ACTION}"
	fi;
}

add() {
	log add "${@}"
	if [ "${1}" = "host" -o "${1}" = "network" -o "${1}" = "net" ]; then
		shift;
		addHost "${@}"
	elif [ "${1}" = "internal" -o "${1}" = "external" -o "${1}" = "local" ]; then
		DIR=${1}
		shift;
		if [ "${1}" = "host" -o "${1}" = "network" -o "${1}" = "net" ]; then
			shift;
			addHost "${DIR}" "${@}"
		else
			echo "Unable to process add rule" >&2
			exit 1;
		fi;
	elif [ "${1}" = "interface" ]; then
		shift;
		interface "${@}"
	elif [ "${1}" = "rule" ]; then
		shift;
		addRule "${@}"
	elif [ "${1}" = "raw" ]; then
		shift;
		applyRule "${@}"
	else
		echo "Unable to process add rule" >&2
		exit 1;
	fi;
}

interface() {
	KEYWORD="to"
	if [ "${1}" = "alias" -o "${1}" = "name" -o "${1}" = "add"  ]; then shift; fi;
	ALIAS=${1};
	shift;
	if [ "${1}" = "to" -o "${1}" = "is" -o "${1}" = "as"  ]; then KEYWORD="${1}"; shift; fi;
	INTERFACE=${1};

	if [ "${KEYWORD}" = "as" ]; then
		TEMP=${ALIAS}
		ALIAS=${INTERFACE}
		INTERFACE=${TEMP}
	fi;

	fwset ${ALIAS} ${INTERFACE}
	fwsettype "INTERFACE" "${ALIAS}" "1"
}

addHost() {
	TYPE="internal"
	if [ "${1}" = "external" -o "${1}" = "internal" -o "${1}" = "local" ]; then
		TYPE="${1}"
		shift;
	fi

	ALIAS=""
	if [ "${1}" = "alias" ]; then
		shift;
		ALIAS=${1}
		shift;
	fi;

	IP=${1}
	shift;

	COMMENT=""

	if [ "${ALIAS}" != "" ]; then
		COMMENT="${ALIAS}"
		fwset ${ALIAS} ${IP}
		if [ "${TYPE}" = "internal" ]; then
			fwsettype "HOST" "${ALIAS}" "1"
			applyRule "-N ${ALIAS}-IN"
			applyRule "-N ${ALIAS}-OUT"
			applyRule "-A FORWARD -d ${IP} -j ${ALIAS}-IN"
			applyRule "-A FORWARD -s ${IP} -j ${ALIAS}-OUT"
		fi;
	elif [ "${TYPE}" = "internal" ]; then
		echo "Internal hosts must have an alias." >&2
		exit 1;
	fi;

	if [ "${1}" = "group" ]; then
		shift;
		GROUP=${1}
		shift
		ACTION="ACCEPT"
		checkGroup ${GROUP}

		if [ "${1}" = "action" ]; then
			shift;
			ACTION="${1}"
			shift;
		fi;

		if [ "${1}" = "comment" ]; then
			shift;
			if [ "${COMMENT}" != "" ]; then COMMENT="${COMMENT} "; fi;
			COMMENT=${COMMENT}"${1}"
			shift;
		fi;

		if [ "${COMMENT}" != "" ]; then
			COMMENT=' -m comment --comment "'${COMMENT}'"'
		fi;

		applyRule "-A 'GROUP-${GROUP}' -s '${IP}' -j ${ACTION} ${COMMENT}"
	fi;
}

checkGroup() {
	GROUP="${1}"

	ISGROUP=`fwgettype "GROUP" "${GROUP}"`
	if [ "${ISGROUP}" != "1" ]; then
		fwsettype "GROUP" "${GROUP}" "1"
		applyRule "-N 'GROUP-${GROUP}'"
	fi;
}

checkGroupChain() {
	GROUP="${1}"
	CHAIN="${2}"

	checkGroup ${GROUP}

	ISGROUP=`fwgettype "GROUPCHAIN" "${GROUP}__${CHAIN}"`
	if [ "${ISGROUP}" != "1" ]; then
		fwsettype "GROUPCHAIN" "${GROUP}__${CHAIN}" "1"
		applyRule "-A '${CHAIN}' -j 'GROUP-${GROUP}'"
	fi;
}
