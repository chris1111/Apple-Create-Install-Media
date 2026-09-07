# Applescript create by chris1111
# Copyright (c) 2020, 2026 chris1111 All rights reserved.
#
# Credit: Apple
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# Version "1.0" by chris1111
# Vars
-- ============================================================

set theAction to button returned of (display dialog "
Welcome Create Install Media
You can create a bootable USB key 
from OS X Maverick 10.9 to macOS Tahoe 26
		
Format your USB Drive with Disk Utility 
in the format Mac OS Extended (Journaled) 
GUID Partition Map
*****************************


To create a USB installation media, you need a 16 GB or larger USB drive.

Starting with macOS Sonoma 14, some 16 GB USB drives are not sufficient, so use a 32 GB USB drive to avoid errors.

NOTE: SIP security and Gatekeeper must be disabled.
When you format the USB media, You must quit Disk Utility to continue " with icon note buttons {"Quit", "Create Install Media"} cancel button "Quit" default button "Create Install Media")

--If Create Install Media
if theAction = "Create Install Media" then
	
	tell application "Disk Utility" to activate
	
	repeat
		if application "Disk Utility" is not running then exit repeat
		delay 1
	end repeat
	activate me
	
	set Volumepath to paragraphs of (do shell script "ls /Volumes")
	set Diskpath to choose from list Volumepath with prompt "
To be able to continue, select the volume
that you just formatted.
Then press the OK button" OK button name "OK" with multiple selections allowed
	
	if Diskpath is false then
		display dialog "Quit Installer" with icon 0 buttons {"EXIT"} default button "EXIT"
		return
	end if
	
	set Diskpath to item 1 of Diskpath -- ⬅️ list → single volume name
	
	try
		set theAction to button returned of (display dialog "

Choose the location of your Install macOS.app" with icon note buttons {"Quit", "10.9 to Tahoe 26"} cancel button "Quit" default button "10.9 to Tahoe 26")
		
		-- Sierra / El Capitan / Yosemite / Mavericks & older auto-get --applicationpath.
		if theAction is in {"10.9 to Tahoe 26"} then
			
			set InstallOSX to choose file of type {"XLSX", "APPL"} default location (path to applications folder) with prompt "Choose your Install macOS.app"
			set OSXInstaller to POSIX path of InstallOSX
			
			-- ✅ Sanity check: is it really a macOS installer?
			set CIMcheck to quoted form of (OSXInstaller & "/Contents/Resources/createinstallmedia")
			set checkResult to do shell script "test -x " & CIMcheck & " && echo yes || echo no"
			if checkResult is "no" then
				display dialog "❌ That app is not a valid macOS installer.
(createinstallmedia not found inside it.)" with icon stop buttons {"OK"} default button "OK"
				return
			end if
			
			-- 🕰️ Sierra / El Capitan / Yosemite / Mavericks need --applicationpath
			set needsAppPath to false
			set nm to name of (info for InstallOSX)
			if nm contains "Sierra" or nm contains "El Capitan" or nm contains "Yosemite" or nm contains "Mavericks" then set needsAppPath to true
			
			delay 2
			set confirmed to button returned of (display dialog "

Please confirm your choice?
Create Install Media from --> " & POSIX path of InstallOSX & "
Install to --> " & Diskpath & "

⚠️ Everything on this volume will be ERASED!" with icon note buttons {"Cancel", "OK"} cancel button "Cancel" default button "OK")
			
			if confirmed is "OK" then
				-- 🚀 RUN WITH REAL PROGRESS BAR
				delay 2
				set finalProgress to createInstallerWithProgress(OSXInstaller, Diskpath, needsAppPath)
				
				set endAction to button returned of (display dialog "✅ Install media created successfully!

" & Diskpath & " is now bootable." with icon note buttons {"Done"} default button "Done" giving up after 30)
				delay 3
			end if
		end if
		
	on error errMsg number errNum
		-- -128 = user pressed Cancel → exit silently
		if errNum is not -128 then
			display dialog "❌ Error: " & errMsg with icon stop buttons {"OK"} default button "OK"
		end if
	end try
end if


-- ============================================================
--  ENGINE — do not touch below unless you know why
-- ============================================================

on createInstallerWithProgress(OSXInstaller, Diskpath, needsAppPath)
	set logFile to "/tmp/cim_progress.log"
	
	-- Normalize: ensure trailing slash on installer path
	if OSXInstaller does not end with "/" then set OSXInstaller to OSXInstaller & "/"
	
	-- Optional --applicationpath (Sierra & older)
	set appPathArg to ""
	if needsAppPath then set appPathArg to " --applicationpath \"" & OSXInstaller & "\""
	
	-- Clean old log
	do shell script "rm -f " & logFile with administrator privileges
	
	-- Start createinstallmedia in BACKGROUND, output → log file
	set startCmd to "sudo \"" & OSXInstaller & "Contents/Resources/createinstallmedia\" --volume /Volumes/\"" & Diskpath & "\"" & appPathArg & " --nointeraction > " & logFile & " 2>&1 &"
	do shell script startCmd with administrator privileges
	
	-- Init progress bar
	set currentProgress to 0
	set progress total steps to 100
	set progress completed steps to 0
	set progress description to "Create Install Media
======================================
Installation time 15 to 25 min on a standard USB key
3 to 5 min on a Disk Ext HD
======================================
Installing macOS!  Wait until it's finished  . . ."
	
	-- Polling loop
	repeat
		delay 1
		
		set logContent to ""
		try
			set logContent to do shell script "cat " & logFile & " 2>/dev/null"
		end try
		
		if logContent is not "" then
			set currentProgress to my calculateTrueProgress(logContent)
			set progress completed steps to (round currentProgress)
			set progress additional description to ((round currentProgress) as string) & "%"
		end if
		
		-- Done?
		if logContent contains "Install media now available" then
			set progress completed steps to 100
			set progress additional description to "100%"
			return 100
		end if
		
		-- Process died without finishing → fail loudly
		set isRunning to do shell script "pgrep -x createinstallmedia > /dev/null && echo yes || echo no"
		if isRunning is "no" and logContent is not "" then
			if logContent does not contain "Install media now available" then
				if (length of logContent) > 400 then
					set logContent to text ((length of logContent) - 399) thru -1 of logContent
				end if
				error "createinstallmedia failed: " & logContent
			end if
		end if
	end repeat
end createInstallerWithProgress


-- 🧮 TRUE weighted progress — auto-detects phase order
on calculateTrueProgress(logContent)
	set AppleScript's text item delimiters to ""
	
	if logContent contains "Install media now available" then return 100
	
	set erasePos to 0
	set copyPos to 0
	set bootPos to 0
	if logContent contains "Erasing disk:" then set erasePos to offset of "Erasing disk:" in logContent
	if logContent contains "Copying to disk:" then set copyPos to offset of "Copying to disk:" in logContent
	if logContent contains "Making disk bootable" then set bootPos to offset of "Making disk bootable" in logContent
	
	set copyFirst to (copyPos > 0 and (bootPos is 0 or copyPos < bootPos))
	
	set maxPos to erasePos
	set lastPhase to "erase"
	if copyPos > maxPos then
		set maxPos to copyPos
		set lastPhase to "copy"
	end if
	if bootPos > maxPos then
		set lastPhase to "boot"
	end if
	
	if lastPhase is "erase" then
		set erasePct to my extractLatestPercentage(logContent, "Erasing disk:")
		return 2 * erasePct / 100
		
	else if lastPhase is "copy" then
		set copyPct to my extractLatestPercentage(logContent, "Copying to disk:")
		if copyFirst then
			return 2 + (95 * copyPct / 100)
		else
			return 5 + (92 * copyPct / 100)
		end if
		
	else if lastPhase is "boot" then
		if copyFirst then
			return 98
		else
			return 4
		end if
	end if
	
	return 0
end calculateTrueProgress


-- 🔍 Latest % for a phase (reads digits BACKWARDS → always newest)
on extractLatestPercentage(logContent, phaseName)
	set AppleScript's text item delimiters to phaseName
	set phaseParts to text items of logContent
	set AppleScript's text item delimiters to ""
	
	if (count of phaseParts) < 2 then return 0
	
	set tailText to item -1 of phaseParts
	
	set AppleScript's text item delimiters to "%"
	set pctParts to text items of tailText
	set AppleScript's text item delimiters to ""
	
	if (count of pctParts) < 2 then return 0
	
	set pctStr to item -2 of pctParts
	
	set cleanNum to ""
	repeat with i from length of pctStr to 1 by -1
		set thisChar to character i of pctStr
		if thisChar is in "0123456789" then
			set cleanNum to thisChar & cleanNum
		else if cleanNum is not "" then
			exit repeat
		end if
	end repeat
	
	try
		return cleanNum as integer
	on error
		return 0
	end try
end extractLatestPercentage
