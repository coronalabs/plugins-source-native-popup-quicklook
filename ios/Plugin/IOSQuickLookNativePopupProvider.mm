// ----------------------------------------------------------------------------
// 
// IOSQuickLookPopupProvider.mm
// Copyright (c) 2013 Corona Labs Inc. All rights reserved.
// 
// ----------------------------------------------------------------------------

#import <QuickLook/QuickLook.h>

#import "CoronaRuntime.h"
#include "CoronaAssert.h"
#include "CoronaEvent.h"
#include "CoronaLua.h"
#include "CoronaLibrary.h"
#include "IOSQuickLookNativePopupProvider.h"

// ----------------------------------------------------------------------------

@interface CoronaQuickLookDelegate : UITableViewController
<
	QLPreviewControllerDataSource,
	QLPreviewControllerDelegate,
	UIDocumentInteractionControllerDelegate
>

@property (nonatomic, assign) lua_State *luaState; // Pointer to the current Lua state
@property (nonatomic) CoronaLuaRef listenerRef; // Reference to store our listener (callback) function
@property (nonatomic, assign) NSMutableDictionary *fileCache; // Dictionary to store filePath's/baseDir etc.
@end

@class CoronaQuickLookDelegate;

static const char kPopupName[] = "quickLook";

// Is the previewController available?
static bool
isPreviewControllerAvailable()
{
	return nil != NSClassFromString( @"QLPreviewController" );
}


// [Lua] native.canShowPopup
static int preview_canShowPopup( lua_State *L )
{
	lua_pushboolean( L, isPreviewControllerAvailable() );
	return 1;
}


// [Lua] native.showPopup
static int preview_showPopup( lua_State *L )
{
	// The result
	int result = 0;
	id<CoronaRuntime> runtime = (id<CoronaRuntime>)CoronaLuaGetContext( L );

	// If the controller is available
	if ( isPreviewControllerAvailable() )
	{
		// Create an instance of our delegate
		CoronaQuickLookDelegate *delegate = [[CoronaQuickLookDelegate alloc] init];

		// Assign the Lua State
		delegate.luaState = L;

		// Assign our runtime view controller
		UIViewController *appViewController = runtime.appViewController;

		// Initialize our fileCache dictionary
		delegate.fileCache = [[NSMutableDictionary alloc] init];

		// Create our arrays
		NSMutableArray *baseDirectories = [[NSMutableArray alloc] init];
		NSMutableArray *filePaths = [[NSMutableArray alloc] init];
		NSMutableArray *fileNames = [[NSMutableArray alloc] init];

		// Set reference to onComplete function
		if ( lua_istable( L, 2 ) )
		{
			// Get listener key
			lua_getfield( L, 2, "listener" );

			// Set the delegates listenerRef to reference the onComplete function (if it exists)
			if ( CoronaLuaIsListener( L, -1, kPopupName ) )
			{
				//printf( "Registered listener\n" );
				delegate.listenerRef = CoronaLuaNewRef( L, -1 );
			}
			// Pop listener key
			lua_pop( L, 1 );

			// files key
			lua_getfield( L, 2, "files" );

			// If this is a table
			if ( lua_istable( L, -1 ) )
			{
				size_t numOfFiles = lua_objlen( L, -1 );
				//printf( "Num tables is: %d\n", numOfFiles );

				if ( numOfFiles > 0 )
				{
					// table is an array of 'path' tables
					for ( int i = 1; i <= numOfFiles; i ++ )
					{
						lua_rawgeti( L, -1, i );

						// Get the filename key
						lua_getfield( L, -1, "filename" );
						// Enforce string type
						if ( lua_type( L, -1 ) != LUA_TSTRING )
						{
							luaL_error( L, "filename parameter must be a string, got: %s", lua_typename( L, lua_type( L, -1 ) ) );
						}
						const char *filename = lua_tostring( L, -1 );
						lua_pop( L, 1 ); // pop filename key

						// Get the baseDir key
						lua_getfield( L, -1, "baseDir" );
						void *baseDir = lua_touserdata( L, -1 );
						lua_pop( L, 1 ); // Pop basedir key

						// Add filename/path to the array
						[fileNames addObject:[NSString stringWithUTF8String:filename]];

						// Add baseDir to the array
						[baseDirectories addObject:[NSValue valueWithPointer:baseDir]];

						// Get full path to file
						CoronaLibraryCallFunction( L, "system", "pathForTable", "t>s", CoronaLuaNormalize( L, -1 ) );
						const char *filePath = lua_tostring( L, -1 );

						// If filePath != null, add this filePath to the delegate's filePath table
						if ( filePath )
						{
							[filePaths addObject:[NSString stringWithUTF8String:filePath]];
							//printf( "filePath is: %s\n", filePath );
						}
						// Pop tables
						lua_pop( L, 2 );
					}
				}
			}
			lua_pop( L, 1 ); // Pop files key
			
			// startIndex key
			lua_getfield( L, -1, "startIndex" );
			// The item index to start the preview at (we use 0 as the default to match non Lua indices)
			int startIndex = 0;
			// If this is a number
			luaL_checktype( L, -1, LUA_TNUMBER );
			// Clamp the number (between 0 and the # of items in the filePaths array)
			startIndex = MIN( MAX( luaL_checknumber( L, -1 ) - 1, 0 ), [filePaths count] );
			//printf( "Start index val after clamping: %d", startIndex );
			lua_pop( L, 2 ); // Pop startIndex key & options table
			
			// Ensure we can preview all items passed from the [lua] file table.
			for ( long i = [fileNames count] -1 ; i >=0 ; i -- )
			{
				// File path to the current item
				NSString *currentItemPath = [filePaths objectAtIndex:i];

				// If we can't display the current item, remove it from our lists
				if ( ! [QLPreviewController canPreviewItem:[NSURL fileURLWithPath:currentItemPath]] )
				{
					//NSLog( @"Can't Preview Item: %@\n", currentItemPath );
					[filePaths removeObjectAtIndex:i];
					[fileNames removeObjectAtIndex:i];
					[baseDirectories removeObjectAtIndex:i];
				}
			}

			// Add objects to our dictionary
			[delegate.fileCache setObject:fileNames forKey:@"fileName"];
			[delegate.fileCache setObject:baseDirectories forKey:@"baseDir"];
			[delegate.fileCache setObject:filePaths forKey:@"filePath"];
			// Cleanup
			[fileNames release];
			[baseDirectories release];
			[filePaths release];
			fileNames = nil;
			baseDirectories = nil;
			filePaths = nil;

			// If there is at least one object in the filePath array (that can be displayed)
			if ( [[delegate.fileCache objectForKey:@"filePath"] count] >= 1 )
			{
				// Create a QLPreviewController instance
				QLPreviewController *previewController = [[QLPreviewController alloc] init];
				previewController.delegate = delegate;
				previewController.dataSource = delegate;
				previewController.currentPreviewItemIndex = startIndex;
				[appViewController presentViewController:previewController animated:YES completion:nil];
			}
			// No valid items in the array, call listener with "failed" action
			else
			{
				// Create the event
				CoronaLuaNewEvent( L, CoronaEventPopupName() ); // event.name
				lua_pushstring( L, "quickLook" ); // event.type
				lua_setfield( L, -2, CoronaEventTypeKey() );
				lua_pushstring( L, "failed" ); // action type
				lua_setfield( L, -2, "action" ); // event.action
				
				// Dispatch the event
				CoronaLuaDispatchEvent( L, delegate.listenerRef, 1 );

				// Free native reference to listener
				CoronaLuaDeleteRef( L, delegate.listenerRef );

				// Null the reference
				delegate.listenerRef = NULL;
				
				// Free the fileCache dictionary
				[delegate.fileCache release];
				delegate.fileCache = nil;
			}
		}
		else
		{
			luaL_error( L, "The second argument to native.showPopup( '%s' ) must be a table", kPopupName );
		}
	}

	return result;
}

// ----------------------------------------------------------------------------

@implementation CoronaQuickLookDelegate

// Number of previous items
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
	// Return the number of items
    return [[self.fileCache objectForKey:@"baseDir"] count];
}

// Current preview item
- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index
{
	// File path to the current item
	NSString *currentItemPath = [[self.fileCache objectForKey:@"filePath"] objectAtIndex:index];

	/*
	// If we can't display the current item
	if ( ! [QLPreviewController canPreviewItem:[NSURL fileURLWithPath:currentItemPath]] )
	{
		// TODO: Should we dispatch an event here?
		NSLog( @"Can't Preview Item: %@\n", currentItemPath );
	}
	*/

	// Return the URL to the current file path
	return [NSURL fileURLWithPath:currentItemPath];
}

// When the controller is requested to dismiss (i.e. when the "done" button is pressed)
- (void)previewControllerWillDismiss:(QLPreviewController *)controller
{
	// If there is a listener
	if ( self.listenerRef )
	{
		// Filename of the current item
		NSString *fileName = [[self.fileCache objectForKey:@"fileName"] objectAtIndex:controller.currentPreviewItemIndex];
		// Base directory of the current item
		void *baseDir = [[[self.fileCache objectForKey:@"baseDir"] objectAtIndex:controller.currentPreviewItemIndex] pointerValue];

		// Create the event
		CoronaLuaNewEvent( self.luaState, CoronaEventPopupName() ); // event.name
		lua_pushstring( self.luaState, "quickLook" ); // event.type
		lua_setfield( self.luaState, -2, CoronaEventTypeKey() );
		lua_pushstring( self.luaState, "done" ); // action type
		lua_setfield( self.luaState, -2, "action" ); // event.action

		// event.file table
		lua_newtable( self.luaState );

		// filename
		lua_pushstring( self.luaState, [fileName UTF8String] );
		lua_setfield( self.luaState, -2, "filename" );

		// Basedir
		lua_pushlightuserdata( self.luaState, baseDir );
		lua_setfield( self.luaState, -2, "baseDir" );
		lua_setfield( self.luaState, -2, "file" ); // event.file (table)

		// Dispatch the event
		CoronaLuaDispatchEvent( self.luaState, self.listenerRef, 1 );

		// Free native reference to listener
		CoronaLuaDeleteRef( self.luaState, self.listenerRef );

		// Null the reference
		self.listenerRef = NULL;
	
		// Free the fileCache dictionary
		[self.fileCache release];
		self.fileCache = nil;
	}
}

@end

CORONA_EXPORT
int luaopen_CoronaProvider_native_popup_quickLook( lua_State *L )
{
	const char *name = lua_tostring( L, 1 ); CORONA_ASSERT( 0 == strcmp( kPopupName, name ) );
	int result = CoronaLibraryProviderNew( L, "native.popup", name, "com.coronalabs" );
	if ( result > 0 )
	{
		static const luaL_Reg kFunctions[] =
		{
			{ "canShowPopup", preview_canShowPopup },
			{ "showPopup", preview_showPopup },

			{ NULL, NULL }
		};
		
		for (const luaL_Reg *l = kFunctions; l->name != NULL; l++)
		{
			lua_pushcfunction(L, l->func);
			lua_setfield(L, -2, l->name);
		}
	}

	return result;
}

// ----------------------------------------------------------------------------
