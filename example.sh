#!/bin/sh

# Don't actually do anything
# mode debug

# Don't echo what is being done
mode silent

# Be fast not safe
mode fast

# IPV6 Mode
mode ipv6

# Settings to use later
fwset LANIF to br0
fwset WANIF to ppp0

# Clear the tables
empty INPUT
empty OUTPUT
empty FORWARD
empty

# Set default policies
policy for INPUT is DROP
policy for OUTPUT is ALLOW
policy for FORWARD is DROP

# Allow local and loopback
allow input on lo
allow input on LANIF

# Allow established
allow all state RELATED,ESTABLISHED

# Our trusted hosts.
add external host alias MIFUNE 2001:470:1f12:d54::2 group TRUSTED
add external host alias SOREN 2001:470:4:598::2 group TRUSTED

# Banned Hosts
# add external host 2001:470:1f12:d54::2 group BANNED action DROP comment "test comment"

# Check both groups
check all group TRUSTED
check all group BANNED

# Our internal hosts.
add host alias XION 2001:4d48:ad51:15df:250:8dff:fe9c:18b0
add host alias NEO 2001:4d48:ad51:15df:224:1dff:fec5:c07b

# Allow ports to neo
allow input protocol tcp on port 22 to NEO
allow input protocol tcp on port 80 to NEO
allow input protocol tcp on port 53 to NEO
allow input protocol udp on port 53 to NEO
allow input protocol tcp on port 25 to NEO
allow input protocol tcp on port 443 to NEO

# allow input protocol ipv6-icmp to XION