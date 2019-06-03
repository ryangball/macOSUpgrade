#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# Copyright (c) 2019 Jamf.  All rights reserved.
#
#       Redistribution and use in source and binary forms, with or without
#       modification, are permitted provided that the following conditions are met:
#               * Redistributions of source code must retain the above copyright
#                 notice, this list of conditions and the following disclaimer.
#               * Redistributions in binary form must reproduce the above copyright
#                 notice, this list of conditions and the following disclaimer in the
#                 documentation and/or other materials provided with the distribution.
#               * Neither the name of the Jamf nor the names of its contributors may be
#                 used to endorse or promote products derived from this software without
#                 specific prior written permission.
#
#       THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#       EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#       WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#       DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#       DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#       (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#       LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#       ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#       (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#       SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# This script was designed to be used in a Self Service policy to ensure specific
# requirements have been met before proceeding with an inplace upgrade of the macOS,
# as well as to address changes Apple has made to the ability to complete macOS upgrades
# silently.
#
# VERSION: v2.7.4
#
# REQUIREMENTS:
#           - Jamf Pro
#           - macOS Clients running version 10.10.5 or later
#           - macOS Installer 10.12.4 or later
#           - eraseInstall option is ONLY supported with macOS Installer 10.13.4+ and client-side macOS 10.13+
#           - Look over the USER VARIABLES and configure as needed.
#
#
# For more information, visit https://github.com/kc9wwh/macOSUpgrade
#
#
# Written by: Joshua Roskos | Jamf
#
# Created On: January 5th, 2017
# Updated On: March 30th, 2019
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# USER VARIABLES
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Specify path to OS installer. Use Parameter 4 in the JSS, or specify here
##Example: /Applications/Install macOS High Sierra.app
OSInstaller="$4"

##Version of Installer OS. Use Parameter 5 in the JSS, or specify here.
##Example Command: /usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallInfo.plist"
##Example: 10.12.5
version="$5"
versionMajor=$( /bin/echo "$version" | /usr/bin/awk -F. '{print $2}' )
versionMinor=$( /bin/echo "$version" | /usr/bin/awk -F. '{print $3}' )

##Custom Trigger used for download. Use Parameter 6 in the JSS, or specify here.
##This should match a custom trigger for a policy that contains just the
##MacOS installer. Make sure that the policy is scoped properly
##to relevant computers and/or users, or else the custom trigger will
##not be picked up. Use a separate policy for the script itself.
##Example trigger name: download-sierra-install
download_trigger="$6"

##MD5 Checksum of InstallESD.dmg
##This variable is OPTIONAL
##Leave the variable BLANK if you do NOT want to verify the checksum (DEFAULT)
##Example Command: /sbin/md5 /Applications/Install\ macOS\ High\ Sierra.app/Contents/SharedSupport/InstallESD.dmg
##Example MD5 Checksum: b15b9db3a90f9ae8a9df0f81741efa2b
installESDChecksum="$7"

##Valid Checksum?  O (Default) for false, 1 for true.
validChecksum=0

##Unsuccessful Download?  0 (Default) for false, 1 for true.
unsuccessfulDownload=0

##Erase & Install macOS (Factory Defaults)
##Requires macOS Installer 10.13.4 or later
##Disabled by default
##Options: 0 = Disabled / 1 = Enabled
##Use Parameter 8 in the JSS.
eraseInstall="$8"
if [[ "${eraseInstall:=0}" != 1 ]]; then eraseInstall=0 ; fi
#macOS Installer 10.13.3 or ealier set 0 to it.
if [ "$versionMajor${versionMinor:=0}" -lt 134 ]; then
    eraseInstall=0
fi

##Enter 0 for Full Screen, 1 for Utility window (screenshots available on GitHub)
##Full Screen by default
##Use Parameter 9 in the JSS.
userDialog="$9"
if [[ ${userDialog:=0} != 1 ]]; then userDialog=0 ; fi

# Control for auth reboot execution.
if [ "$versionMajor" -ge 14 ]; then
    # Installer of macOS 10.14 or later set cancel to auth reboot.
    cancelFVAuthReboot=1
else
    # Installer of macOS 10.13 or earlier try to do auth reboot.
    cancelFVAuthReboot=0
fi

##Title of OS
macOSname=$(/bin/echo "$OSInstaller" | /usr/bin/sed -E 's/(.+)?Install(.+)\.app\/?/\2/' | /usr/bin/xargs)

##Title to be used for userDialog (only applies to Utility Window)
title="$macOSname Upgrade"

##Heading to be used for userDialog
heading="Please wait as we prepare your computer for $macOSname..."

##Title to be used for userDialog
description="This process will take approximately 5-10 minutes.
Once completed your computer will reboot and begin the upgrade."

##Description to be used prior to downloading the OS installer
dldescription="We need to download $macOSname to your computer, this will \
take several minutes."

##Jamf Helper HUD Position if macOS Installer needs to be downloaded
##Options: ul (Upper Left); ll (Lower Left); ur (Upper Right); lr (Lower Right)
##Leave this variable empty for HUD to be centered on main screen
dlPosition="ul"

##Icon to be used for userDialog
##Default is macOS Installer logo which is included in the staged installer package
icon="$OSInstaller/Contents/Resources/InstallAssistant.icns"

##First run script to remove the installers after run installer
finishOSInstallScriptFilePath="/usr/local/jamfps/finishOSInstall.sh"

##Launch deamon settings for first run script to remove the installers after run installer
osinstallersetupdDaemonSettingsFilePath="/Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist"

##Launch agent settings for filevault authenticated reboots
osinstallersetupdAgentSettingsFilePath="/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"

##Amount of time (in seconds) to allow a user to connect to AC power before moving on
acPowerWaitTimer="120"

##Icon to display during the AC Power warning
warnIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"

##Icon to display when errors are found
errorIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FUNCTIONS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

wait_for_ac_power() {
    # Loop for 120 seconds until either AC Power is detected or the timer is up
    sysRequirementErrors=()
    /bin/echo "Waiting for AC power..."
    while [[ "$acPowerWaitTimer" -gt "0" ]]; do
        if /usr/bin/pmset -g ps | grep "AC Power" > /dev/null ; then
            /bin/echo "Power Check: OK - AC Power Detected"
            ps -p "$jamfHelperPowerPID" > /dev/null && kill "$jamfHelperPowerPID"; wait "$jamfHelperPowerPID" 2>/dev/null
            return
        fi
        sleep 1
        ((acPowerWaitTimer--))
    done
    ps -p "$jamfHelperPowerPID" > /dev/null && kill "$jamfHelperPowerPID"; wait "$jamfHelperPowerPID" 2>/dev/null
    sysRequirementErrors+=("• Is connected to AC power")
    /bin/echo "Power Check: ERROR - No AC Power Detected"
}

downloadInstaller() {
    /bin/echo "Downloading macOS Installer..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
        -windowType hud -windowPosition $dlPosition -title "$title" -alignHeading center -alignDescription left -description "$dldescription" \
        -lockHUD -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" -iconSize 100 &
    ##Capture PID for Jamf Helper HUD
    jamfHUDPID=$!
    ##Run policy to cache installer
    /usr/local/jamf/bin/jamf policy -event "$download_trigger"
    ##Kill Jamf Helper HUD post download
    /bin/kill "${jamfHUDPID}"
}

get_power_status() {
    ##Check if device is on battery or ac power
    ##If not allow user to connect to power for specified time period
    if /usr/bin/pmset -g ps | grep "AC Power" > /dev/null ; then
        /bin/echo "Power Check: OK - AC Power Detected"
    else
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Waiting for AC Power Connection" -icon "$warnIcon" -description "Please connect your computer to power using an AC power adapter. This process will continue once AC power is detected." &
        jamfHelperPowerPID=$(/bin/echo $!)
        wait_for_ac_power
    fi
}

get_free_space() {
    ##Check if free space > 15GB
    osMajor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $2}' )
    osMinor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $3}' )
    if [[ $osMajor -eq 12 ]] || [[ $osMajor -eq 13 && $osMinor -lt 4 ]]; then
        freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Available Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
    else
        freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
    fi

    if [[ ${freeSpace%.*} -ge 15000000000 ]]; then
        /bin/echo "Disk Check: OK - ${freeSpace%.*} Bytes Free Space Detected"
    else
        sysRequirementErrors+=("• Has at least 15GB of Free Space")
        /bin/echo "Disk Check: ERROR - ${freeSpace%.*} Bytes Free Space Detected"
    fi
}

verifyChecksum() {
    if [[ "$installESDChecksum" != "" ]]; then
        osChecksum=$( /sbin/md5 -q "$OSInstaller/Contents/SharedSupport/InstallESD.dmg" )
        if [[ "$osChecksum" == "$installESDChecksum" ]]; then
            /bin/echo "Checksum: Valid"
            validChecksum=1
            return
        else
            /bin/echo "Checksum: Not Valid"
            /bin/echo "Beginning new dowload of installer"
            /bin/rm -rf "$OSInstaller"
            /bin/sleep 2
            downloadInstaller
        fi
    else
        ##Checksum not specified as script argument, assume true
        validChecksum=1
        return
    fi
}

cleanExit() {
    ps -p "$caffeinatePID" > /dev/null && kill "$caffeinatePID"; wait "$caffeinatePID" 2>/dev/null
    ## Remove Script
    /bin/rm -f "$finishOSInstallScriptFilePath" 2>/dev/null
    /bin/rm -f "$osinstallersetupdDaemonSettingsFilePath" 2>/dev/null
    /bin/rm -f "$osinstallersetupdAgentSettingsFilePath" 2>/dev/null
    exit "$1"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# SYSTEM CHECKS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Caffeinate
/usr/bin/caffeinate -dis &
caffeinatePID=$!

##Get Current User
currentUser=$( /usr/bin/stat -f %Su /dev/console )

##Check if FileVault Enabled
fvStatus=$( /usr/bin/fdesetup status | head -1 )

##Run system requirement checks
get_power_status
get_free_space

##Don't waste the users time, exit here if system requirements are not met
if [[ "${#sysRequirementErrors[@]}" -ge 1 ]]; then
    /bin/echo "Launching jamfHelper Dialog (Requirements Not Met)..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$errorIcon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure your computer meets the following requirements:

$( printf '\t%s\n' "${sysRequirementErrors[@]}" )

If you continue to experience this issue, please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1

    cleanExit 1
fi

##Check for existing OS installer
loopCount=0
while [[ $loopCount -lt 3 ]]; do
    if [ -e "$OSInstaller" ]; then
        /bin/echo "$OSInstaller found, checking version."
        OSVersion=$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$OSInstaller/Contents/SharedSupport/InstallInfo.plist")
        /bin/echo "OSVersion is $OSVersion"
        if [ "$OSVersion" = "$version" ]; then
            /bin/echo "Installer found, version matches. Verifying checksum..."
            verifyChecksum
        else
            ##Delete old version.
            /bin/echo "Installer found, but old. Deleting..."
            /bin/rm -rf "$OSInstaller"
            /bin/sleep 2
            downloadInstaller
        fi
        if [ "$validChecksum" == 1 ]; then
            unsuccessfulDownload=0
            break
        fi
    else
        downloadInstaller
    fi
    unsuccessfulDownload=1
    ((loopCount++))
done

if (( unsuccessfulDownload == 1 )); then
    /bin/echo "macOS Installer Downloaded 3 Times - Checksum is Not Valid"
    /bin/echo "Prompting user for error and exiting..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$errorIcon" -heading "Error Downloading $macOSname" -description "We were unable to prepare your computer for $macOSname. Please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1
    cleanExit 0
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# CREATE FIRST BOOT SCRIPT
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

/bin/mkdir -p /usr/local/jamfps

/bin/cat << EOF > "$finishOSInstallScriptFilePath"
#!/bin/bash
## First Run Script to remove the installer.
## Clean up files
/bin/rm -fr "$OSInstaller"
/bin/sleep 2
## Update Device Inventory
/usr/local/jamf/bin/jamf recon
## Remove LaunchAgent and LaunchDaemon
/bin/rm -f "$osinstallersetupdAgentSettingsFilePath"
/bin/rm -f "$osinstallersetupdDaemonSettingsFilePath"
## Remove Script
/bin/rm -fr /usr/local/jamfps
exit 0
EOF

/usr/sbin/chown root:admin "$finishOSInstallScriptFilePath"
/bin/chmod 755 "$finishOSInstallScriptFilePath"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH DAEMON
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

/bin/cat << EOF > "$osinstallersetupdDaemonSettingsFilePath"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jamfps.cleanupOSInstall</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>$finishOSInstallScriptFilePath</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

##Set the permission on the file just made.
/usr/sbin/chown root:wheel "$osinstallersetupdDaemonSettingsFilePath"
/bin/chmod 644 "$osinstallersetupdDaemonSettingsFilePath"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH AGENT FOR FILEVAULT AUTHENTICATED REBOOTS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
if [ "$cancelFVAuthReboot" -eq 0 ]; then
    ##Determine Program Argument
    if [[ $osMajor -ge 11 ]]; then
        progArgument="osinstallersetupd"
    elif [[ $osMajor -eq 10 ]]; then
        progArgument="osinstallersetupplaind"
    fi

    /bin/cat << EOP > "$osinstallersetupdAgentSettingsFilePath"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.apple.install.osinstallersetupd</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>MachServices</key>
    <dict>
        <key>com.apple.install.osinstallersetupd</key>
        <true/>
    </dict>
    <key>TimeOut</key>
    <integer>300</integer>
    <key>OnDemand</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
        <string>$OSInstaller/Contents/Frameworks/OSInstallerSetup.framework/Resources/$progArgument</string>
    </array>
</dict>
</plist>
EOP

    ##Set the permission on the file just made.
    /usr/sbin/chown root:wheel "$osinstallersetupdAgentSettingsFilePath"
    /bin/chmod 644 "$osinstallersetupdAgentSettingsFilePath"

fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# APPLICATION
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Launch jamfHelper
if [ ${userDialog} -eq 0 ]; then
    /bin/echo "Launching jamfHelper as FullScreen..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "" -icon "$icon" -heading "$heading" -description "$description" &
    jamfHelperPID=$!
else
    /bin/echo "Launching jamfHelper as Utility Window..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "$heading" -description "$description" -iconSize 100 &
    jamfHelperPID=$!
fi

##Load LaunchAgent
if [[ ${fvStatus} == "FileVault is On." ]] && \
   [[ ${currentUser} != "root" ]] && \
   [[ ${cancelFVAuthReboot} -eq 0 ]] ; then
    userID=$( /usr/bin/id -u "${currentUser}" )
    /bin/launchctl bootstrap gui/"${userID}" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
fi

##Begin Upgrade
/bin/echo "Launching startosinstall..."

##Check if eraseInstall is Enabled
if [[ $eraseInstall == 1 ]]; then
    eraseopt='--eraseinstall'
    /bin/echo "Script is configured for Erase and Install of macOS."
fi

osinstallLogfile="/var/log/startosinstall.log"
if [ "$versionMajor" -ge 14 ]; then
    eval "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" 2>&1 &
else
    eval "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" --applicationpath "\"$OSInstaller\"" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" 2>&1 &
fi
/bin/sleep 3

cleanExit 0