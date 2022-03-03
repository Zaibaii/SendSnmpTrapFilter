#!/bin/sh

# Import of the module to filter the sending email of snmp traps in order to avoid the flood
. $(dirname "$0")/"SendSnmpTrapFilter.sh"

# Declaration of email addresses
sToaddr="email1@domain.com, email2@domain.com" # Receiver
sFromaddr="sender@domain.com" # Sender

# Sample - Standard
sTestReturn1=$(fTrapFilter "catatest1" "[.1.3.6.1.4.1.9.9.41.2.0.1]")
fSendTrap "$sTestReturn1" "From: catatest1\nOid: [.1.3.6.1.4.1.9.9.41.2.0.1]\nDescription: test" "[TRAP] catatest1"

# Sample - Custom
sTestReturn2=$(fTrapFilter "catatest2" "[.1.3.6.1.2.1.17.0.2]" "15" "6" "1")
fSendTrap "$sTestReturn2" "From: catatest2\nOid: [.1.3.6.1.2.1.17.0.2]\nDescription: test" "[TRAP] catatest2" "$sToaddr" "$sFromaddr"

if [ $# = 7 ]; then
	# Sample - Concrete Standard
	sReturn1=$(fTrapFilter "$2" "$4")
	fSendTrap "$sReturn1" "From: $2\nOid: $4\nDescription: $6" "[TRAP] $2 - Standard: $3"

	# Sample - Concrete Custom
	sReturn2=$(fTrapFilter "$2" "$4" "15" "6" "1")
	fSendTrap "$sReturn2" "From: $2\nOid: $4\nStatus: $5\nReason: $6\nDescription: $7" "[TRAP] $2 - Custom: $3 - $7" "$sToaddr" "$sFromaddr"
fi

# To testing the concrete examples, execute the following command in a terminal
#./_Sample.sh "ID test" "device with a space" "Name of the snmp trap" "[Oid test]" "Status test" "Reason test or the description" "The description"

exit 1
