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

		TABLE=`fwgettype "internal" "__table"`
		if [ "${TABLE}" = "filter" -o "${TABLE}" = "__table" ]; then
			TABLE=""
		else
			TABLE=" -t ${TABLE}"
		fi;

		if [ "${IS_DEBUG}" = "1" ]; then
			echo "${IPT}${TABLE} "${@}""
		else
			eval ${IPT}${TABLE} "${@}"
			RES=${?}
			if [ "${IS_STRICT}" = "1" -a "${RES}" != "0" ]; then
				echo "# Error with iptables command." >&2
				exit 1;
			fi;
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
	elif [ "${1}" = "strict" ]; then
		if [ "${IS_STRICT}" != "1" ]; then
			export IS_STRICT="1"
		else
			export IS_STRICT="0"
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
	RES=`which ${BIN} 2>/dev/null`;
	if [ "${RES}" = "" ]; then
		RES=`which xtables-multi 2>/dev/null`;
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

# Show a deprecatation notice.
deprecated() {
	echo -n "# NOTE: '${1}' is deprecated. " >&2
	if [ "" != "${2}" ]; then
		echo "Instead you should use: ${2}" >&2
	else
		echo "" >&2
	fi;
	if [ "${IS_STRICT}" = "1" ]; then
		exit 1;
	fi;
}

# Log a line
log() {
	if [ "${IS_SILENT}" != "1" -a "${NOLOG}" != "1" ]; then
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
	elif [ "${1}" = 'ALL' -o "${1}" = 'all' ]; then
		applyRule "-F INPUT"
		applyRule "-F FORWARD"
		applyRule "-F OUTPUT"
		applyRule "-F"
		applyRule "-X"
	else
		applyRule "-F '${1}'"
	fi;
}

# NOOP, for formatting
begin() { echo -n ""; }
end() { echo -n ""; }

checkTable() {
	TABLE="${1}"
	RES=""
	if [ "${TABLE}" = "" -o "${TABLE}" = "default" -o "${TABLE}" = "__table" ]; then
		RES="filter"
	elif [ "${FWMODE}" = "ipv6" ]; then
		RES=`cat /proc/net/ip6_tables_names | grep "^${TABLE}$"`
	elif [ "${FWMODE}" = "ipv4" ]; then
		RES=`cat /proc/net/ip_tables_names | grep "^${TABLE}$"`
	fi;
	echo ${RES};
}

# Run a rule against a different table than the currently active table.
with() {
	log with "${@}"
	if [ "${1}" = "table" ]; then
		shift;
		doTableWith "${@}"
	fi;
}

# Change the currently active table.
table() {
	log table "${@}"
	doTable "${@}"
}

doTable() {
	TABLE=${1}
	if [ "${TABLE}" = "default" ]; then TABLE="filter"; fi;
	TABLE=`checkTable ${TABLE}`
	if [ "${TABLE}" != "" ]; then
		fwsettype "internal" "__table" "${TABLE}"
	else
		echo "# Invalid table name: ${1}"
		exit 1;
	fi;
}

doTableWith() {
	OLDTABLE=`fwgettype "internal" "__table"`
	doTable "${@}"
	shift;
	if [ "${1}" != "" ]; then
		NOLOG="1"
		if [ "${1}" = "with" ]; then
			echo "# Nested 'with' commands are not allowed" >&2
			exit 1;
		else
			eval "${@}"
		fi;
		if [ "${OLDTABLE}" = "__table" ]; then OLDTABLE=""; fi
		fwsettype "internal" "__table" "${OLDTABLE}"
		NOLOG="0"
	fi;
}

# Work with the input chain
input() {
	log input "${@}"
	doChainCommand input "${@}"
}
# Work with the forward chain
forward() {
	log forward "${@}"
	doChainCommand forward "${@}"
}
# Work with the output chain
output() {
	log output "${@}"
	doChainCommand output "${@}"
}
# Work with input/forward/output chains at the same time.
all() {
	log all "${@}"
	doChainCommand input "${@}"
	doChainCommand forward "${@}"
	doChainCommand output "${@}"
}

doChainCommand() {
	CHAIN=""

	if [ "${1}" = "input" ]; then CHAIN="INPUT";
	elif [ "${1}" = "output" ]; then CHAIN="OUTPUT";
	elif [ "${1}" = "forward" ]; then CHAIN="FORWARD";
	elif [ "${1}" = "prerouting" ]; then CHAIN="PREROUTING";
	elif [ "${1}" = "postrouting" ]; then CHAIN="POSTROUTING";
	fi
	shift;

	if [ "${1}" = "policy" ]; then
		shift;
		if [ "${1}" = "is" ]; then shift; fi
		VALUE="${1}"
		if [ "${CHAIN}" != "" -a "${VALUE}" != "" ]; then
			applyRule "-P '${CHAIN}' '${VALUE}'"
		fi;
	fi;
}

# Set the policy for a chain
policy() {
	log policy "${@}"
	deprecated policy "<chain> policy is <policy>"
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

masquerade() {
	log masquerade "${@}"
	OLDTABLE=`fwgettype "internal" "__table"`
	doTable "nat"
	addRule MASQUERADE postrouting "${@}"
	if [ "${OLDTABLE}" = "__table" ]; then OLDTABLE=""; fi
	doTable "${OLDTABLE}"
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
	elif [ "${1}" = "prerouting" ]; then
		CHAIN="PREROUTING";
	elif [ "${1}" = "postrouting" ]; then
		CHAIN="POSTROUTING";
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
		elif [ "${1}" = "to" -o "${1}" = "out" ]; then
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
	elif [ "${1}" = "member" ]; then
		shift;
		addMember "${@}"
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

addMember() {
	DIRECTION=""
	MEMBERTYPE=""

	if [ "${1}" = "direction" ]; then shift; fi;
        if [ "${1}" = "outbound" -o "${1}" = "inbound" ]; then
                DIRECTION="${1}"
                shift;
        fi;

	if [ "${1}" = "group" -o "${1}" = "network" -o "${1}" = "alias" ]; then
		MEMBERTYPE="${1}"
		shift;
	fi;

	MEMBER="${1}"
	shift;

	if [ "${1}" = "direction" ]; then shift; fi;
	if [ "${1}" = "outbound" -o "${1}" = "inbound" ]; then
		DIRECTION="${1}"
		shift;
	fi;

	if [ "${1}" = "to" ]; then shift; fi;

	if [ "${1}" = "group" ]; then
		shift;
		GROUP=${1}
		shift
		ACTION="ACCEPT"
		checkGroup ${GROUP}

	        if [ "${1}" = "direction" ]; then shift; fi;
	        if [ "${1}" = "outbound" -o "${1}" = "inbound" ]; then
	                DIRECTION="${1}"
	                shift;
	        fi;

		if [ "${1}" = "action" ]; then
			shift;
			ACTION="${1}"
			shift;
		fi;

		COMMENT=""
		if [ "${1}" = "comment" ]; then
			shift;
			if [ "${COMMENT}" != "" ]; then COMMENT="${COMMENT} "; fi;
			COMMENT=${COMMENT}"${1}"
			shift;
		fi;

		if [ "${COMMENT}" != "" ]; then
			COMMENT=' -m comment --comment "'${COMMENT}'"'
		fi;

		if [ "${MEMBERTYPE}" = "" ]; then
			# Figure out the type...
			ISGROUP=`fwgettype "GROUP" "${MEMBER}"`
			ISALIAS=`fwgettype "ALIAS" "${MEMBER}"`
			if [ "${ISGROUP}" = "1" ]; then
				MEMBERTYPE="group"
			elif [ "${ISALIAS}" = "1" ]; then
				MEMBERTYPE="alias"
			else
				MEMBERTYPE="network"
			fi;
		fi;


		if [ "${MEMBERTYPE}" = "group" ]; then
			if [ "${ACTION}" != "ACCEPT" ]; then
                                echo "Action can not be specified when adding a group as a member."
                                exit 1;
                        fi;
			if [ "${DIRECTION}" != "" ]; then
				echo "Direction can not be specified when adding a group as a member."
				exit 1;
			fi;
			checkGroup ${MEMBER}
			applyRule "-A 'GROUP-${GROUP}' -j 'GROUP-${MEMBER}' ${COMMENT}"
		elif [ "${MEMBERTYPE}" = "alias" -o  "${MEMBERTYPE}" = "network" ]; then
			if [ "${MEMBERTYPE}" = "alias" ]; then
				MEMBER=`fwget ${MEMBER}`
				if [ "${MEMBER}" = "" ]; then
					echo "Unknown member."
					exit 1;
				fi;
			fi;

			if [ "${DIRECTION}" = "outbound" -o "${DIRECTION}" = "" ]; then
				applyRule "-A 'GROUP-${GROUP}' -d '${MEMBER}' -j '${ACTION}' ${COMMENT}"
			fi;
			if [ "${DIRECTION}" = "inbound" -o "${DIRECTION}" = "" ]; then
				applyRule "-A 'GROUP-${GROUP}' -s '${MEMBER}' -j '${ACTION}' ${COMMENT}"
			fi;
		else
			echo "Unknown membership."
			exit 1;
		fi;
	fi;
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
		fwsettype "ALIAS" "${ALIAS}" "1"
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

		DIRECTION=""
		if [ "${1}" = "direction" ]; then shift; fi;
		if [ "${1}" = "outbound" -o "${1}" = "inbound" ]; then
			DIRECTION="${1}"
			shift;
		fi;


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

		if [ "${DIRECTION}" = "inbound" -o "${DIRECTION}" = "" ]; then
			applyRule "-A 'GROUP-${GROUP}' -s '${IP}' -j ${ACTION} ${COMMENT}"
		fi;
		if [ "${DIRECTION}" = "outbound" -o "${DIRECTION}" = "" ]; then
			applyRule "-A 'GROUP-${GROUP}' -d '${IP}' -j ${ACTION} ${COMMENT}"
		fi;
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
