-- 
-- Abstract: Quick Look sample app
--  
-- Version: 1.0
-- 
-- Sample code is MIT licensed, see http://www.coronalabs.com/links/code/license
-- Copyright (C) 2013 Corona Labs Inc. All Rights Reserved.
--
-- Demonstrates how to use Corona to preview items with the iOS Quick Look controller

local widget = require( "widget" )

-- Display a background
local background = display.newImageRect( "assets/background.png", 320, 480 )
background.x = display.contentCenterX
background.y = display.contentCenterY

-- Listener for the quick look callback
local function quickLookListener( event )
	print( "name: ", event.name )
	print( "action: ", event.action )
	print( "type: ", event.type )

	-- event.file, filename and baseDir of the last file previewed
	if "table" == type( event.file ) then
		print( "event.file: {" )
		for k, v in pairs( event.file ) do
			print( k, ":", v )
			--[[
			-- KEYS/VALS
			k = filename
			v = value

			k = baseDir
			v = the baseDirectory of the file
			--]]
		end
		print( "}" )
	end
end

-- Options to pass to the quick look popup
local popupOptions = 
{
	files = -- Files you wish to load into the quick look preview
	{ 
		{ filename = "sampleFiles/PDF Document.pdf", baseDir = system.ResourceDirectory },
		{ filename = "sampleFiles/Image Document.jpg", baseDir = system.ResourceDirectory },
		{ filename = "sampleFiles/HTML Document.html", baseDir = system.ResourceDirectory },
		{ filename = "sampleFiles/Text Document.txt", baseDir = system.ResourceDirectory },
	},
	startIndex = 1, -- The file you wish to start the preview at. Defaults is 1 (if omitted).
	listener = quickLookListener, -- Callback listener
}

-- Called when the widget button is released
local function onRelease( event )
	-- Check if the quickLook popup is available
	local popupIsAvailable = native.canShowPopup( "quickLook" )

	if popupIsAvailable then
		-- Show the quick look popup
		native.showPopup( "quickLook", popupOptions )
	end
end

-- Button to show the quick look popup
local button = widget.newButton
{
	label = "Show QuickLook",
	onRelease = onRelease,
}
button.x = display.contentCenterX
button.y = display.contentCenterY
