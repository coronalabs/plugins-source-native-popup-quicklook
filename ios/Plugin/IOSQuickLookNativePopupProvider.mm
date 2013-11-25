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
@property (nonatomic) Corona::Lua::Ref listenerRef; // Reference to store our listener (callback) function
@property (nonatomic, assign) NSMutableArray *filePath;
@end

@class CoronaQuickLookDelegate;

// ----------------------------------------------------------------------------

class IOSQuickLookNativePopupProvider
{
	public:
		typedef IOSQuickLookNativePopupProvider Self;

	public:
		static int Open( lua_State *L );
		static int Finalizer( lua_State *L );
		static Self *ToLibrary( lua_State *L );

	protected:
		IOSQuickLookNativePopupProvider();
		bool Initialize( void *platformContext );
		
	public:
		UIViewController* GetAppViewController() const { return fAppViewController; }

	public:
		static int canShowPopup( lua_State *L );
		static int showPopup( lua_State *L );

	private:
		UIViewController *fAppViewController;
};

// ----------------------------------------------------------------------------


namespace Corona
{

// ----------------------------------------------------------------------------

class IOSQuickLookNativePopupProvider
{
	public:
		typedef IOSQuickLookNativePopupProvider Self;

	public:
		static int Open( lua_State *L );
		static int Finalizer( lua_State *L );
		static Self *ToLibrary( lua_State *L );

	protected:
		IOSQuickLookNativePopupProvider();
		bool Initialize( void *platformContext );

	public:
		UIViewController* GetAppViewController() const { return fAppViewController; }
	
	public:
		static int canShowPopup( lua_State *L );
		static int showPopup( lua_State *L );

	private:
		UIViewController *fAppViewController;
};

// ----------------------------------------------------------------------------

static const char kPopupName[] = "quickLook";
static const char kMetatableName[] = __FILE__; // Globally unique value

int
IOSQuickLookNativePopupProvider::Open( lua_State *L )
{
	CoronaLuaInitializeGCMetatable( L, kMetatableName, Finalizer );
	void *platformContext = CoronaLuaGetContext( L );

	const char *name = lua_tostring( L, 1 ); CORONA_ASSERT( 0 == strcmp( kPopupName, name ) );
	int result = CoronaLibraryProviderNew( L, "native.popup", name, "com.coronalabs" );

	if ( result > 0 )
	{
		int libIndex = lua_gettop( L );

		Self *library = new Self;

		if ( library->Initialize( platformContext ) )
		{
			static const luaL_Reg kFunctions[] =
			{
				{ "canShowPopup", canShowPopup },
				{ "showPopup", showPopup },

				{ NULL, NULL }
			};

			// Register functions as closures, giving each access to the
			// 'library' instance via ToLibrary()
			{
				lua_pushvalue( L, libIndex ); // push library
				CoronaLuaPushUserdata( L, library, kMetatableName ); // push library ptr
				luaL_openlib( L, NULL, kFunctions, 1 );
				lua_pop( L, 1 ); // pop library
			}
		}
	}

	return result;
}

int
IOSQuickLookNativePopupProvider::Finalizer( lua_State *L )
{
	Self *library = (Self *)CoronaLuaToUserdata( L, 1 );
	delete library;
	return 0;
}

IOSQuickLookNativePopupProvider::Self *
IOSQuickLookNativePopupProvider::ToLibrary( lua_State *L )
{
	// library is pushed as part of the closure
	Self *library = (Self *)CoronaLuaToUserdata( L, lua_upvalueindex( 1 ) );
	return library;
}

// ----------------------------------------------------------------------------

IOSQuickLookNativePopupProvider::IOSQuickLookNativePopupProvider()
:	fAppViewController( nil )
{
}

bool
IOSQuickLookNativePopupProvider::Initialize( void *platformContext )
{
	bool result = ( ! fAppViewController );

	if ( result )
	{
		id<CoronaRuntime> runtime = (id<CoronaRuntime>)platformContext;
		fAppViewController = runtime.appViewController; // TODO: Should we retain?
	}

	return result;
}


// Is the previewController available?
static bool
isPreviewControllerAvailable()
{
	return nil != NSClassFromString( @"QLPreviewController" );
}


// [Lua] native.canShowPopup
int
IOSQuickLookNativePopupProvider::canShowPopup( lua_State *L )
{
	if ( isPreviewControllerAvailable() )
	{
		lua_pushboolean( L, true );
	}
	else
	{
		lua_pushboolean( L, false );
	}
	return 1;
}


// [Lua] native.showPopup
int
IOSQuickLookNativePopupProvider::showPopup( lua_State *L )
{
	using namespace Corona;

	Self *context = ToLibrary( L );
	
	// The result
	int result = 0;

	if ( context && isPreviewControllerAvailable() )
	{
		Self& library = * context;
		
		// Create an instance of our delegate
		CoronaQuickLookDelegate *delegate = [[CoronaQuickLookDelegate alloc] init];
		
		// Assign the Lua State
		delegate.luaState = L;
		
		// Assign our runtime view controller
		UIViewController *appViewController = library.GetAppViewController();
		
		// Initialize the filePath array
		delegate.filePath = [[NSMutableArray alloc] init];
		
		// Set reference to onComplete function
		if ( lua_istable( L, 2 ) )
		{
			// Get listener key
			lua_getfield( L, 2, "listener" );
			
			// Set the delegates listenerRef to reference the onComplete function (if it exists)
			if ( Lua::IsListener( L, -1, kPopupName ) )
			{
				//printf( "Registered listener\n" );
				delegate.listenerRef = Lua::NewRef( L, -1 );
			}
			// Pop listener key
			lua_pop( L, 1 );
			
			// files key
			lua_getfield( L, 2, "files" );
			
			// If this is a table
			if ( lua_istable( L, -1 ) )
			{
				int numOfFiles = lua_objlen( L, -1 );
				//printf( "Num tables is: %d\n", numOfFiles );
				
				if ( numOfFiles > 0 )
				{
					// table is an array of 'path' tables
					for ( int i = 1; i <= numOfFiles; i++ )
					{
						lua_rawgeti( L, -1, i );
						CoronaLibraryCallFunction( L, "system", "pathForTable", "t>s", CoronaLuaNormalize( L, -1 ) );
						const char *filePath = lua_tostring( L, -1 );
						
						// If filePath != null, add this filePath to the delegate's filePath table
						if ( filePath )
						{
							[delegate.filePath addObject:[NSString stringWithUTF8String:filePath]];
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
			if ( lua_isnumber( L, -1 ) )
			{
				// Clamp the number (between 0 and the # of items in the filePath array)
				startIndex = MIN( MAX( luaL_checknumber( L, -1 ) - 1, 0 ), [delegate.filePath count] );
				//printf( "Start index val after clamping: %d", startIndex );
			}
			lua_pop( L, 1 ); // Pop startIndex key

			// Create a QLPreviewController
			QLPreviewController *previewController = [[QLPreviewController alloc] init];
			previewController.delegate = delegate;
			previewController.dataSource = delegate;
			previewController.currentPreviewItemIndex = startIndex;
			[appViewController presentModalViewController:previewController animated:YES];
		}
		else
		{
			luaL_error( L, "The second argument to native.showPopup( '%s' ) must be a table", kPopupName );
		}
	}

	return result;
}

// ----------------------------------------------------------------------------

} // namespace Corona

// ----------------------------------------------------------------------------

@implementation CoronaQuickLookDelegate

// Number of previous items
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller
{
	// Return the number of items
    return [self.filePath count];
}

// Current preview item
- (id <QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index
{
	// File path to the current item
	NSString *currentItemPath = [self.filePath objectAtIndex:index];

	// If we can't display the current item
	if ( ! [QLPreviewController canPreviewItem:[NSURL fileURLWithPath:currentItemPath]] )
	{
		// TODO: Should we dispatch an event here?
		//NSLog( @"Can't Preview Item: %@\n", currentItemPath );
	}
	
	// Return the URL to the current file path
	return [NSURL fileURLWithPath:currentItemPath];
}

// When the controller is requested to dismiss (i.e. when the "done" button is pressed)
- (void)previewControllerWillDismiss:(QLPreviewController *)controller
{
	// The url of the current preview item
	NSURL *currentItemUrl = (NSURL *)controller.currentPreviewItem;
	// The filename of the current preview item
	NSString *filename = [[currentItemUrl path] lastPathComponent];
	
	//NSLog( @"Current preview item index: %d\n", controller.currentPreviewItemIndex ); // Index of current preview item
	//NSLog( @"Current preview item is: %@\n", controller.currentPreviewItem );
	//NSLog( @"Filename is:%@\n", filename );
		
	// The directory path we are going to dispatch back to Lua
	const char *directoryPath = NULL;
	
	// Check if file exists in resource directory
	NSString *fileFromResourceDirectory = [[NSBundle mainBundle] pathForResource:filename ofType:nil];
	BOOL doesFileResideInResourceDirectory = [[NSFileManager defaultManager] fileExistsAtPath:fileFromResourceDirectory];
	
	// Check if the file exists in the Documents directory
	NSString *documentsDirectoryPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *fileFromDocumentsDirectory = [documentsDirectoryPath stringByAppendingPathComponent:filename];
	BOOL doesFileResideInDocumentsDirectory = [[NSFileManager defaultManager] fileExistsAtPath:fileFromDocumentsDirectory];
	
	// Check if the file exists in the Temporary directory
	NSString *fileFromTemporaryDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
	BOOL doesFileResideInTemporaryDirectory = [[NSFileManager defaultManager] fileExistsAtPath:fileFromTemporaryDirectory];
	
	// Check if the file exists in the Caches directory
	NSString *cachespath = [NSSearchPathForDirectoriesInDomains( NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *fileFromCachesDirectory = [cachespath stringByAppendingString:[NSString stringWithFormat:@"/caches/%@", filename]];
	BOOL doesFileResideInCachesDirectory = [[NSFileManager defaultManager] fileExistsAtPath:fileFromCachesDirectory];

	// If the file exists in the Resource Directory
	if ( doesFileResideInResourceDirectory )
	{
		directoryPath = "ResourceDirectory";
		//printf( "%s resides in resource directory\n", [filename UTF8String] );
	}
	
	// If the file exists in the Documents Directory
	if ( doesFileResideInDocumentsDirectory )
	{
		directoryPath = "DocumentsDirectory";
		//printf( "%s resides in documents directory\n", [filename UTF8String] );
	}
	
	// If the file exists in the Temporary Directory
	if ( doesFileResideInTemporaryDirectory )
	{
		directoryPath = "TemporaryDirectory";
		//printf( "%s resides in temporary directory\n", [filename UTF8String] );
	}
	
	// If the file exists in the Caches Directory
	if ( doesFileResideInCachesDirectory )
	{
		directoryPath = "CachesDirectory";
		//printf( "%s resides in caches directory\n", [filename UTF8String] );
	}
	
	// Create the event
	CoronaLuaNewEvent( self.luaState, CoronaEventPopupName() ); // event.name
	lua_pushstring( self.luaState, "quickLook" ); // event.type
	lua_setfield( self.luaState, -2, CoronaEventTypeKey() );
	lua_pushstring( self.luaState, "done" ); // action type
	lua_setfield( self.luaState, -2, "action" ); // event.action

	// If directoryPath isn't NULL
	if ( directoryPath )
	{
		// event.file table
		lua_newtable( self.luaState );
		
		// filename
		lua_pushstring( self.luaState, [filename UTF8String] );
		lua_setfield( self.luaState, -2, "filename" );
		
		// baseDir
		lua_getglobal( self.luaState, "system" );
		lua_getfield( self.luaState, -1, directoryPath );
		lua_setfield( self.luaState, -3, "baseDir" );
		lua_pop( self.luaState, 1 ); // Pop the system table
		lua_setfield( self.luaState, -2, "file" ); // event.file (table)
	}
	
	// Dispatch the event
	CoronaLuaDispatchEvent( self.luaState, self.listenerRef, 1 );
				
	// Free native reference to listener
	CoronaLuaDeleteRef( self.luaState, self.listenerRef );
		
	// Null the reference
	self.listenerRef = NULL;
}

@end

// Export

CORONA_EXPORT
int luaopen_CoronaProvider_native_popup_quickLook( lua_State *L )
{
	return Corona::IOSQuickLookNativePopupProvider::Open( L );
}

// ----------------------------------------------------------------------------
