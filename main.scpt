# Applescript create by chris1111
# Copyright (c) 2020, 2026 chris1111 All rights reserved.
# No right on OpenCore Bootloader
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
Welcome to Create Install Media
You can create a bootable USB drive
from OS X Mavericks 10.9 to macOS Tahoe 26. 

To create a USB installation media, you need a 16 GB or larger USB drive.

Starting with macOS Sonoma 14, some 16 GB USB drives are not sufficient, so use a 32 GB USB drive to avoid errors.

NOTE: SIP security and Gatekeeper must be disabled.

You must Quit Disk Utilty when you finished to format the USB Media." with icon note buttons {"Quit", "Create Install Media"} cancel button "Quit" default button "Create Install Media")

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
	
	set Diskpath to item 1 of Diskpath -- list -> single volume name
	
	try
		set theAction to button returned of (display dialog "

Choose the location of your Install macOS.app" with icon note buttons {"Quit", "10.9 to Tahoe 26"} cancel button "Quit" default button "10.9 to Tahoe 26")
		
		if theAction is in {"10.9 to Tahoe 26"} then
			
			set InstallOSX to choose file of type {"XLSX", "APPL"} default location (path to applications folder) with prompt "Choose your Install macOS.app"
			set OSXInstaller to POSIX path of InstallOSX
			
			-- Sanity check: is it really a macOS installer?
			set CIMcheck to quoted form of (OSXInstaller & "/Contents/Resources/createinstallmedia")
			set checkResult to do shell script "test -x " & CIMcheck & " && echo yes || echo no"
			if checkResult is "no" then
				display dialog "That app is not a valid macOS installer.
(createinstallmedia not found inside it.)" with icon stop buttons {"OK"} default button "OK"
				return
			end if
			
			-- Classify by NAME (High Sierra's plist reports "13.6.06" - names don't lie)
			-- LEGACY = Mavericks / Yosemite / El Capitan / Sierra / High Sierra
			set nm to name of (info for InstallOSX)
			set isLegacy to false
			if nm contains "Mavericks" then set isLegacy to true
			if nm contains "Yosemite" then set isLegacy to true
			if nm contains "El Capitan" then set isLegacy to true
			if nm contains "Sierra" then set isLegacy to true
			
			if isLegacy then
				set formatText to "Legacy"
			else
				set formatText to "Modern"
			end if
			
			-- --applicationpath only for Sierra 10.12 and older
			set needsAppPath to false
			if isLegacy then
				if (nm contains "Sierra" and nm does not contain "High Sierra") then set needsAppPath to true
				if nm contains "El Capitan" then set needsAppPath to true
				if nm contains "Yosemite" then set needsAppPath to true
				if nm contains "Mavericks" then set needsAppPath to true
			end if
			
			delay 2
			set confirmed to button returned of (display dialog "

Please confirm your choice?
Create Install Media from --> " & POSIX path of InstallOSX & "
Install to --> " & Diskpath & "

App name: " & nm & "
Engine: " & formatText & "

⚠️: Everything on this volume will be ERASED!" with icon note buttons {"Cancel", "OK"} cancel button "Cancel" default button "OK")
			
			if confirmed is "OK" then
				delay 2
				set finalProgress to createInstallerWithProgress(OSXInstaller, Diskpath, needsAppPath, isLegacy)
				
				set endAction to button returned of (display dialog "Install media created successfully!

" & Diskpath & " is now bootable." with icon note buttons {"Done"} default button "Done" giving up after 30)
				delay 3
				
			end if
		end if
		
	on error errMsg number errNum
		-- -128 = user pressed Cancel -> exit silently
		if errNum is not -128 then
			display dialog "Error: " & errMsg with icon stop buttons {"OK"} default button "OK"
		end if
	end try
end if


-- ============================================================
--  ENGINE
--  START COMMAND = the proven one for ALL installers
--
--  MODERN: log percentages (accurate steps) + blind-window
--          creep -> THE PROVEN TAHOE 51% ENGINE (untouched)
--  LEGACY: smooth landing curve - glides from 2% toward 96%,
--          arriving right when "Done." lands. df removed:
--          block restores show "full" from minute one and
--          it caused the instant-90% jump.
-- ============================================================

on createInstallerWithProgress(OSXInstaller, Diskpath, needsAppPath, isLegacy)
	set logFile to "/tmp/cim_progress.log"
	
	-- Normalize: ensure trailing slash on installer path
	if OSXInstaller does not end with "/" then set OSXInstaller to OSXInstaller & "/"
	
	-- Optional --applicationpath (Sierra & older)
	set appPathArg to ""
	if needsAppPath then set appPathArg to " --applicationpath \"" & OSXInstaller & "\""
	
	-- Clean old log
	do shell script "rm -f " & logFile with administrator privileges
	
	-- THE PROVEN START COMMAND - identical for legacy and modern
	set startCmd to "sudo \"" & OSXInstaller & "Contents/Resources/createinstallmedia\" --volume /Volumes/\"" & Diskpath & "\"" & appPathArg & " --nointeraction > " & logFile & " 2>&1 &"
	do shell script startCmd with administrator privileges
	
	-- Refocus right after the password prompt (as in the visible version)
	activate me
	
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
	
	-- Polling loop (structure of the proven GUI-visible version)
	repeat
		delay 1
		
		set logContent to ""
		try
			set logContent to do shell script "cat " & logFile & " 2>/dev/null"
		end try
		
		-- Done? Modern: "Install media now available"
		--        Legacy: "Done." appears when the buffer flushes at exit
		if logContent contains "Install media now available" then
			set progress completed steps to 100
			set progress additional description to "100%"
			return 100
		end if
		if logContent contains "Done." and logContent does not contain "fail" then
			set progress completed steps to 100
			set progress additional description to "100%"
			return 100
		end if
		
		if logContent is not "" then
			set newProgress to 0
			
			if isLegacy then
				-- LEGACY: smooth landing curve (the glide you saw
				-- at 46%/51%). No df, no io - just a calm approach
				-- to 96% that arrives as "Done." lands. Final hop 4%.
				set newProgress to currentProgress + (96 - currentProgress) / 100
			else
				-- MODERN: log percentages ONLY (df lies on full sticks)
				set newProgress to my calculateTrueProgress(logContent)
				if newProgress is 2 or newProgress is 4 then
					-- Blind window: erase done, copy not started.
					-- Tahoe flushes "Making disk bootable" only when
					-- copy begins, so the gap reads as 2 -> creep gently.
					set creep to currentProgress + 0.05
					if creep > 12 then set creep to 12
					set newProgress to creep
				end if
			end if
			
			if newProgress > currentProgress then
				set currentProgress to newProgress
			end if
			set progress completed steps to (round currentProgress)
			set progress additional description to ((round currentProgress) as string) & "%"
		end if
		
		-- Process died without finishing -> fail loudly
		set isRunning to do shell script "pgrep -x createinstallmedia > /dev/null && echo yes || echo no"
		if isRunning is "no" and logContent is not "" then
			if logContent does not contain "Install media now available" then
				if logContent contains "Done." and logContent does not contain "fail" then
					-- legacy success caught at process exit
					set progress completed steps to 100
					set progress additional description to "100%"
					return 100
				end if
				if (length of logContent) > 400 then
					set logContent to text ((length of logContent) - 399) thru -1 of logContent
				end if
				error "createinstallmedia failed: " & logContent
			end if
		end if
	end repeat
end createInstallerWithProgress


-- 🧮 MODERN progress : the proven percentage parsing
on calculateTrueProgress(logContent)
	set AppleScript's text item delimiters to ""
	
	if logContent contains "Install media now available" then return 100
	
	set erasePos to 0
	set copyPos to 0
	set bootPos to 0
	if logContent contains "Erasing disk" then set erasePos to offset of "Erasing disk" in logContent
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
		set erasePct to my extractLatestPercentage(logContent, "Erasing disk")
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


-- 🔍 Latest % for a phase (reads digits BACKWARDS -> always newest)
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
