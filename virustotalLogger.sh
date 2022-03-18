#!/bin/zsh

####
## Copyright 2022 Buoy Health, Inc.

## Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.

## Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
####

## Author: Matt Hrono
## MacAdmins: @matt_h

## Slack webhook URL
webhookURL=""

## Directory where your autopkg run logs are stored
## NOTE: Do NOT include a trailing slash or this will break
logLocation=""

## Get the latest log file path
newLog=$(ls -t "$logLocation" | head -n 1)

## Make sure we have an actual autopkg run log
if [[ "$newLog" =~ ^(autopkg-run-for-)202[0-9]-[0-1][0-9]-[0-3][0-9]-[0-9]{6}.log ]]; then
	newLogPath="$logLocation/$newLog"
	echo "Captured filename is a valid autopkg run log, continuing..." >> $newLogPath
else
	curl -X POST -sH 'Content-type: application/json' --data '{"text":"Invalid AutoPkg run log. VirusTotal logger unable to run."}' $webhookURL
	exit 1
fi

## Check to see if any packages were checked against VirusTotal during the last run
## If none, exit cleanly
if [[ ! $(cat $newLogPath | grep virustotal.com) ]]; then
	echo "No packages checked, exiting..." >> $newLogPath
	exit 0
fi

## If above checks pass without exiting, grab the VirusTotal results from the log and send to a Slack webhook
while read line; do
	echo "Sending log $line to Slack..." >> $newLogPath
	packageName=$(echo $line | awk -F" " '{$NF=""; print $0}')
	scanResults=$(echo $line | awk -F" " '{print $NF}')
	logEntry="$packageName - $scanResults"
	curl -X POST -sH 'Content-type: application/json' --data '{"text":"VirusTotal result for '"$logEntry"'"}' $webhookURL
done < <(cat $newLogPath | awk '/virustotal.com/' | sed 's/https.*$//')
