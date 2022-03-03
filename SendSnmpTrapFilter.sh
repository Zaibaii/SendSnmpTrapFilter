#!/bin/sh

# Author: Zaibai
# This Shell module allows to filter the sending email of snmp traps to avoid flooding.
# It works with snmptt among others.

##########
# This function manages the filtering of snmp traps
# Usage Syntax:
# FunctionName DeviceName SNMP-OID [ResetNumberOccurrenceAfterXHour=5 NumberOccurrenceBeforeFiltering=20 FilteringDurationInHour=10]
# Sample - Standard: fTrapFilter "device-name1" "[.1.3.6.1.4.1.9.9.41.2.0.1]"
# Sample - Custom: fTrapFilter "device-name2" "[.1.3.6.1.2.1.17.0.2]" "10" "30" "5"
# Return value of the function:
# 0 = Cancelled/filtered mail
# 1 = Sending the mail
# 2 = Sending the mail in indicating the flood and the duration of the filtering
##########
fTrapFilter()
{
	# Variable - reset (just in case)
	unset iResetOccurrenceAfterHour
	unset iOccurrenceMax
	unset iFilteringTimeHour
	unset iReturn

	# Variable - Argument
	sDevice="$1"
	sOid="$2"
	iResetOccurrenceAfterHour="${3:-5}"
	iOccurrenceMax="${4:-20}"
	iFilteringTimeHour="${5:-10}"
	
	# Variable - Other
	fBdd="/var/log/snmptt/bddTrapFilter.log"
	[ $iTest -eq 1 ] && fBdd="bddTrapFilter.log"
	sNotFound="NotFound"
	sDateTimeNow=$(date +"%Y-%m-%d %H:%M:%S")
	
	# We create the file $fBdd if not present
	if [ ! -f "$fBdd" ]; then
		touch "$fBdd"
		chmod 644 "$fBdd"
	fi

	# We recover the information necessary for the processing
	sSearch=$(grep --fixed-strings --line-number "$sDevice;$sOid;" $fBdd || echo $sNotFound)
	sDateTimeOccurrence=$(printf '%s' "$sSearch" | awk -F ";" -v var="$sDateTimeNow" '{print ($3 == "" ? var : $3)}')
	iOccurrence=$(printf '%s' "$sSearch" | awk -F ";" '{print ($4 == "" ? 1 : $4)}')
	iLine=$(printf '%s' "$sSearch" | awk -F ":" '{print ($1 ~ /^[0-9]+$/ ? $1 : 0)}')
	iDateTimeNowSecond=$(date --date "${sDateTimeNow}" +%s)
	iDateTimeOccurrenceSecond=$(date --date "${sDateTimeOccurrence}" +%s)
	iDateTimeDiffSecond=$(($iDateTimeNowSecond-$iDateTimeOccurrenceSecond))
	iDateTimeDiffHour=$(($iDateTimeDiffSecond/3600))

	# If the database does not know this combination ("$sDevice;$sOid;") then we add it
	if [ "$sSearch" = "$sNotFound" ]; then
		echo "$sDevice;$sOid;$sDateTimeNow;$iOccurrence" >> $fBdd
	# Else, if the last occurrence is less than $iResetOccurrenceAfterHour hours or than the filtering is in progress, then we increment the counter
	elif ([ $iOccurrence -lt $iOccurrenceMax ] && [ $iDateTimeDiffHour -lt $iResetOccurrenceAfterHour ]) || ([ $iOccurrence -ge $iOccurrenceMax ] && [ $iDateTimeDiffHour -lt $iFilteringTimeHour ]); then
		iOccurrence=$(($iOccurrence+1))
		sed -i "${iLine}s/.*/${sDevice};${sOid};${sDateTimeOccurrence};${iOccurrence}/" "$fBdd"
	# Else we reset the counter
	else
		iOccurrence=1
		sed -i "${iLine}s/.*/${sDevice};${sOid};${sDateTimeNow};${iOccurrence}/" "$fBdd"
	fi
	
	# If the counter exceeds $iOccurrenceMax and the last occurrence is less than $iFilteringTimeHour hours then we return 0 (cancelled/filtered mail)
	if [ $iOccurrence -gt $iOccurrenceMax ] && [ $iDateTimeDiffHour -lt $iFilteringTimeHour ]; then
		[ -z $iReturn ] && iReturn=0
	# Else if the counter is equal at $iOccurrenceMax we return 2 (mail sent in indicating the flood and the duration of the filtering)
	elif [ $iOccurrence -eq $iOccurrenceMax ]; then
		[ -z $iReturn ] && iReturn=2
		# We set the current date and time as the starting point for the duration of the flood
		sed -i "${iLine}s/.*/${sDevice};${sOid};${sDateTimeNow};${iOccurrence}/" "$fBdd"
	# Else we return 1 (we send the mail)
	else
		[ -z $iReturn ] && iReturn=1
	fi

	# In case of a test, the different values obtained are displayed
	if [ $iTest -eq 1 ]; then
		echo '\n------------ TEST fTrapFilter ------------'
		echo "Device: $sDevice"
		echo "Oid: $sOid"
		echo "Reset the number of occurrences after: $iResetOccurrenceAfterHour hours"
		echo "Number of occurrences before filtering: $iOccurrenceMax"
		echo "Filtering duration: $iFilteringTimeHour hours"
		echo "Combination found (Device;Oid;): $sSearch"
		echo "Date of the first occurrence (or start of filtering): $sDateTimeOccurrence"
		echo "Current number of occurrences (after modification): $iOccurrence"
		echo "Location in the database: Line $iLine"
		echo "Timestamp of the first occurrence (or start of filtering): $iDateTimeOccurrenceSecond seconds"
		echo "Current timestamp: $iDateTimeNowSecond seconds"
		echo "Difference between the two timestamps in seconds: $iDateTimeDiffSecond seconds"
		echo "Difference between the two timestamps in hours: $iDateTimeDiffHour hours"
		echo "Returned values (0:cancelled/filtered;1:OK;2:OK+flood/indicated filtering duration): $iReturn $iFilteringTimeHour"
		echo '------------ TEST fTrapFilter ------------'
	fi
	
	# Returned values
	echo "$iReturn $iFilteringTimeHour"
}

##########
# This function manages the sending of snmp traps by mail
# Usage Syntax:
# FunctionName ResultfTrapFilter ContentMail SubjectMail [AddressesTo="emailto1@domain.com, emailto2@domain.com" AddresseFrom="emailfrom@domain.com"]
# Sample - Standard: fSendTrap "1 10" "From: $2\nOid: $4\nDescription: $6" "[TRAP] $2: $3"
# Sample - Custom: fSendTrap "2 15" "From: $2\nOid: $4\nNode: $5\nPort: $6\nCode: $7\nDescription: $8" "[TRAP] $2: $3" "email1@domain.com, email2@domain.com" "sender@domain.com"
##########
fSendTrap()
{
	# Variable - reset (just in case)
	unset sReceiver
	unset sSender

	# Variable - Argument
	iReturnST=$(echo "$1" | cut -d ' ' -f 1)
	iFilteringTimeHourST=$(echo "$1" | cut -d ' ' -f 2)
	sBody="$2"
	sSubject="$3"
	sReceiver="${4:-emailto1@domain.com, emailto2@domain.com}"
	sSender="${5:-emailfrom@domain.com}"
	[ $iTest -eq 1 ] && sReceiver="emailtestto1@domain.com"
	[ $iTest -eq 1 ] && sSender="emailtestfrom@domain.com"
	
	# Management of mail sending
	# 0 = Cancelled/filtered mail
	# 1 = Sending the mail
	# 2 = Sending the mail in indicating the flood and the duration of the filtering
	case $iReturnST in
		1)
			echo "$sBody" | mail -r "$sSender" -s "$sSubject" "$sReceiver"
			;;
		
		2)
			sBody="$sBody \nFiltering: $iFilteringTimeHourST hours"
			sSubject=$(echo "$sSubject" | sed -e 's/\[TRAP\]/[TRAP][FLOOD]/')
			echo "$sBody" | mail -r "$sSender" -s "$sSubject" "$sReceiver"
			;;
	esac
	
	# In case of a test, the different values obtained are displayed
	if [ $iTest -eq 1 ]; then
		sBodyTmp=$(printf '%s' "$sBody" | sed -e 's/\\n/\n /g')
		echo '\n------------  TEST fSendTrap  ------------'
		echo "Values returned by fTrapFilter (0:cancelled/filtered;1:OK;2:OK+flood/indicated filtering duration): $iReturnST $iFilteringTimeHourST"
		echo "Sender: $sSender"
		echo "To: $sReceiver"
		echo "Subject: $sSubject"
		echo "Body: "
		printf ' %b\n' "$sBodyTmp"
		echo '------------  TEST fSendTrap  ------------\n '
	fi
}

# This function is executed if the script is called with the "test" argument
fMainTF()
{
	# Test - Standard
	sTest1=$(fTrapFilter "device name test1" "[.1.3.6.1.4.1.9.9.41.2.0.1]")
	sTestReturn1=$(echo "$sTest1" | tail -n1)
	sTest1=$(echo "$sTest1" | sed '$d')
	echo "$sTest1"
	fSendTrap "$sTestReturn1" "From: device name test1\nOid: [.1.3.6.1.4.1.9.9.41.2.0.1]\nDescription: test" "[TRAP] device name test1"
	
	# Test - Custom
	sTest2=$(fTrapFilter "device name test2" "[.1.3.6.1.2.1.17.0.2]" "15" "6" "1")
	sTestReturn2=$(echo "$sTest2" | tail -n1)
	sTest2=$(echo "$sTest2" | sed '$d')
	echo "$sTest2"
	fSendTrap "$sTestReturn2" "From: device name test2\nOid: [.1.3.6.1.2.1.17.0.2]\nDescription: test" "[TRAP] device name test2"
	
	exit 1
}

# We check if it is a test
iTest=0
arg1_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
if [ "$arg1_lower" = "test" ]; then
	iTest=1
	shift
    fMainTF "$@"
fi

# Possible improvement
# Database archiving
