//
//  AppDelegate.m
//  Parrot Status
//
//  Created by Vincent Le Normand on 29/10/2014.
//  Copyright (c) 2014 Vincent Le Normand. All rights reserved.
//

#import "AppDelegate.h"
#import <IOBluetooth/IOBluetooth.h>
#import <Sparkle/Sparkle.h>
#import "PFMoveApplication.h"
#import <Quartz/Quartz.h>

typedef NS_ENUM(NSInteger, PSState) {
	PSAskingStateInit,
	PSAskingStateConnected,
};

@interface AppDelegate ()
@property (weak) IBOutlet NSWindow *advancedBatteryWindow;
@property (weak) IBOutlet SUUpdater *updater;
@end

@interface AppDelegate(SharedFileListExample)
- (void)enableLoginItemWithLoginItemsReference:(LSSharedFileListRef )theLoginItemsRefs forPath:(NSString *)appPath;
- (void)disableLoginItemWithLoginItemsReference:(LSSharedFileListRef )theLoginItemsRefs forPath:(NSString *)appPath;
- (BOOL)loginItemExistsWithLoginItemReference:(LSSharedFileListRef)theLoginItemsRefs forPath:(NSString *)appPath ;
@end

@implementation AppDelegate {
	NSStatusItem * statusItem;
	BluetoothRFCOMMChannelID channelId;
	IOBluetoothRFCOMMChannel * mRfCommChannel;
	PSState state;
	
	// State
	unsigned char batteryLevel;
	BOOL batteryCharging;
	NSString * version;
	NSString * name;
	BOOL autoConnection;
	BOOL ancPhoneMode;
	BOOL noiseCancel;
	BOOL louReedMode;
	BOOL concertHall;
	CFAbsoluteTime showUntilDate;
	
	CFMachPortRef eventTap;
}

+ (void) initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
															  @"ShowBatteryNotifications":@YES,
															  @"ShowBatteryAboutToDieNotifications":@YES,
															  @"BatteryNotificationLevels":@[@"20%",@"10%"],
															  @"ShowBatteryPercentage":@NO,
															  @"ShowBatteryIcon":@YES,
															  @"HiddenWhenDisconnected":@NO,
															  }];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
	PFMoveToApplicationsFolderIfNecessary();
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
	if (loginItems) {
		[self enableLoginItemWithLoginItemsReference:loginItems forPath:appPath];
	}
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"HiddenWhenDisconnected"] && state != PSAskingStateConnected) {
		showUntilDate = CFAbsoluteTimeGetCurrent()+30.;
		[self updateStatusItem];
		[statusItem popUpStatusItemMenu:statusItem.menu];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(31 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[self updateStatusItem];
		});
	}
	return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[self setupStatusItem];
	[IOBluetoothDevice registerForConnectNotifications:self selector:@selector(connected:fromDevice:)];
}

- (void) setupStatusItem {
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
	[self updateStatusItem];
	statusItem.highlightMode = YES;
	NSMenu * myMenu = [[NSMenu alloc] initWithTitle:@"Test"];
	myMenu.delegate = self;
	statusItem.menu = myMenu;
	statusItem.button.appearsDisabled = YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
	if (loginItems) {
		[self disableLoginItemWithLoginItemsReference:loginItems forPath:appPath];
	}

}

- (void) updateStatusItem {
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"HiddenWhenDisconnected"]) {
		if(state != PSAskingStateConnected && showUntilDate<CFAbsoluteTimeGetCurrent() ) {
			[statusItem.statusBar removeStatusItem:statusItem];
			statusItem = nil;
			return;
		}
		else {
			if(statusItem==nil) {
				[self setupStatusItem];
			}
		}
	}
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowBatteryIcon"]) {
		CGFloat imageWidth = (state == PSAskingStateConnected) ? 22 : 16;
		statusItem.button.image = [NSImage imageWithSize:NSMakeSize(imageWidth, 16) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
			[[NSColor colorWithDeviceWhite:0.0 alpha:0.9] set];
			NSBezierPath  * headset = [NSBezierPath bezierPath];
			[headset moveToPoint:NSMakePoint(1.5, 4.5)];
			[headset curveToPoint:NSMakePoint(9.5, 4.5) controlPoint1:NSMakePoint(4.5, 16.5) controlPoint2:NSMakePoint(6.5, 16.5)];
			[headset appendBezierPathWithOvalInRect:NSMakeRect(1.5, 0.5, 2, 6)];
			[headset appendBezierPathWithOvalInRect:NSMakeRect(7.5, 0.5, 2, 6)];
			[headset setLineWidth:2.5];
			[headset stroke];
			if( state == PSAskingStateConnected) {
				[[NSColor blackColor] set];
				NSRect batteryRect = NSMakeRect(11.5,0.5,6,13);
				[[NSBezierPath bezierPathWithRect:batteryRect] stroke];
				[[NSBezierPath bezierPathWithRect:NSMakeRect(NSMidX(batteryRect)-2., NSMaxY(batteryRect), 4., 2.)] fill];
				batteryRect = NSInsetRect(batteryRect, 1, 1);
				
				if(batteryCharging)
				{
					NSRect lightningRect = NSInsetRect(batteryRect, 1, 1);
					NSBezierPath * lightning = [NSBezierPath bezierPath];
					[lightning moveToPoint:NSMakePoint(NSMaxX(lightningRect), NSMaxY(lightningRect))];
					[lightning lineToPoint:NSMakePoint(NSMinX(lightningRect), NSMidY(lightningRect)-1.)];
					[lightning lineToPoint:NSMakePoint(NSMaxX(lightningRect), NSMidY(lightningRect)+1.)];
					[lightning lineToPoint:NSMakePoint(NSMinX(lightningRect), NSMinY(lightningRect))];
					[lightning stroke];
				}
				
				
				batteryRect.size.height *= ((CGFloat)batteryLevel)/100.0;
				[[NSBezierPath bezierPathWithRect:batteryRect] fill];
			}
			//		NSRectFill(dstRect);
			return YES;
		}];
		[statusItem.image setTemplate:YES];
	}
	else {
		statusItem.image = nil;
	}
	if([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowBatteryPercentage"]) {
		if( state == PSAskingStateConnected) {
			if(batteryCharging) {
				statusItem.button.title = NSLocalizedString(@"Charging", @"");
			}
			else {
				statusItem.button.title = [NSString stringWithFormat:NSLocalizedString(@"%i%%", @""),batteryLevel];
			}
		}
		else {
			statusItem.button.title = NSLocalizedString(@"-", @"");
		}
		statusItem.length = NSVariableStatusItemLength;
	}
	else {
		statusItem.button.title = nil;
		statusItem.length = NSSquareStatusItemLength;
	}
	statusItem.button.appearsDisabled = state != PSAskingStateConnected;
	statusItem.button.imagePosition = NSImageRight;
}

CGEventRef modifiersChanged( CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon ) {
	if(CGEventGetType(event) != kCGEventFlagsChanged) {
		return NULL;
	}
	AppDelegate * myself = (__bridge AppDelegate *)(refcon);
	[myself menuNeedsUpdate:myself->statusItem.menu event:[NSEvent eventWithCGEvent:event]];
	[myself->statusItem.menu update];
	return NULL;
}

- (void) menuWillOpen:(NSMenu *)menu {
	eventTap = CGEventTapCreate(kCGHIDEventTap,kCGHeadInsertEventTap,kCGEventTapOptionListenOnly,CGEventMaskBit(kCGEventFlagsChanged),&modifiersChanged,(__bridge void *)(self));
	CFRunLoopSourceRef	eventSrc = CFMachPortCreateRunLoopSource(NULL, eventTap, 0);
	if (eventSrc) {
		CFRunLoopAddSource([[NSRunLoop currentRunLoop] getCFRunLoop], eventSrc, kCFRunLoopCommonModes);
		CFRelease(eventSrc);
		CGEventTapEnable(eventTap, true);
	}
}

- (void) menuDidClose:(NSMenu *)menu{
	CGEventTapEnable(eventTap, false);
	eventTap = NULL;
}

- (void)menuNeedsUpdate:(NSMenu*)menu event:(NSEvent*)event {
	[menu removeAllItems];
	if( state == PSAskingStateConnected) {
		[menu addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Connected to %@", @""),name] action:NULL keyEquivalent:@""];
		[menu addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Version %@", @""),version] action:NULL keyEquivalent:@""];
		NSMenuItem * batteryMenuItem = nil;
		NSMenu * batteryMenu = [[NSMenu alloc] initWithTitle:@""];
		if(batteryCharging) {
			batteryMenuItem =[menu addItemWithTitle:NSLocalizedString(@"Battery level: Charging", @"") action:NULL keyEquivalent:@""];
		}
		else {
			batteryMenuItem =[menu addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Battery level: %i%%", @""),batteryLevel] action:NULL keyEquivalent:@""];
		}
		batteryMenuItem.submenu = batteryMenu;
		
		BOOL showBatteryPercentage = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowBatteryPercentage"];
		BOOL showBatteryIcon = [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowBatteryIcon"];
		
		[[batteryMenu addItemWithTitle:NSLocalizedString(@"Show Battery Icon Only", @"") action:@selector(showBatteryIconOnly:) keyEquivalent:@""] setState:(showBatteryIcon&&!showBatteryPercentage)?NSOnState:NSOffState];
		[[batteryMenu addItemWithTitle:NSLocalizedString(@"Show Battery Icon And Percentage", @"") action:@selector(showBatteryIconAndText:) keyEquivalent:@""] setState:(showBatteryIcon&&showBatteryPercentage)?NSOnState:NSOffState];
		[[batteryMenu addItemWithTitle:NSLocalizedString(@"Show Battery Percentage Only", @"") action:@selector(showBatteryTextOnly:) keyEquivalent:@""] setState:(!showBatteryIcon&&showBatteryPercentage)?NSOnState:NSOffState];
		
		[menu addItem:[NSMenuItem separatorItem]];
		[[menu addItemWithTitle:NSLocalizedString(@"Noise cancellation", @"") action:@selector(toggleNoiseCancellation:) keyEquivalent:@""] setState:noiseCancel?NSOnState:NSOffState];
		[[menu addItemWithTitle:NSLocalizedString(@"Auto connection", @"") action:@selector(toggleAutoConnect:) keyEquivalent:@""] setState:autoConnection?NSOnState:NSOffState];
		[[menu addItemWithTitle:NSLocalizedString(@"Lou Reed mode", @"") action:@selector(toggleLouReed:) keyEquivalent:@""] setState:louReedMode?NSOnState:NSOffState];
		[[menu addItemWithTitle:NSLocalizedString(@"Concert hall mode", @"") action:@selector(toggleConcertHall:) keyEquivalent:@""] setState:concertHall?NSOnState:NSOffState];
	}
	else {
		NSMenuItem * notConnected = [menu addItemWithTitle:NSLocalizedString(@"Not connected",@"") action:NULL keyEquivalent:@""];
		notConnected.submenu = [[NSMenu alloc] initWithTitle:@""];
		if([[NSUserDefaults standardUserDefaults] boolForKey:@"HiddenWhenDisconnected"]) {
			[notConnected.submenu addItemWithTitle:NSLocalizedString(@"Show when disconnected", @"") action:@selector(showWhenDisconnected:) keyEquivalent:@""];
		}
		else {
			[notConnected.submenu addItemWithTitle:NSLocalizedString(@"Hide when disconnected", @"") action:@selector(hideWhenDisconnected:) keyEquivalent:@""];
		}
	}
	if([event modifierFlags] & NSAlternateKeyMask) {
		[menu addItemWithTitle:NSLocalizedString(@"Battery notifications…", @"") action:@selector(showAdvancedBatteryOptions:) keyEquivalent:@""];
	}
	else {
		[[menu addItemWithTitle:NSLocalizedString(@"Battery notifications", @"") action:@selector(toogleBatteryNotifications:) keyEquivalent:@""] setState:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowBatteryNotifications"]?NSOnState:NSOffState];
	}
	
	[menu addItem:[NSMenuItem separatorItem]];
	if([event modifierFlags] & NSAlternateKeyMask) {
		NSMenuItem * checkForUpdates = [menu addItemWithTitle:NSLocalizedString(@"Check For Updates…", @"") action:@selector(about:) keyEquivalent:@""];
		[checkForUpdates setTarget:self.updater];
		[checkForUpdates setAction:@selector(checkForUpdates:)];
	}
	else {
		[menu addItemWithTitle:NSLocalizedString(@"About", @"") action:@selector(about:) keyEquivalent:@""];
	}
	
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:NSLocalizedString(@"Quit", @"") action:@selector(terminate:) keyEquivalent:@""];
}

- (void)menuNeedsUpdate:(NSMenu*)menu {
	[self menuNeedsUpdate:menu event:[NSApp currentEvent]];
}

#pragma mark -
#pragma mark IOBluetoothUserNotification

static NSArray * uuidServices = nil;
static NSArray * uuidServicesZik2 = nil;
- (void)connected:(IOBluetoothUserNotification *)note fromDevice:(IOBluetoothDevice *)device
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
        //0ef0f502-f0ee-46c9-986c-54ed027807fb Zik 1
        //8b6814d3-6ce7-4498-9700-9312c1711f63 Zik 2
		NSUUID * uuid = [[NSUUID alloc] initWithUUIDString:@"0ef0f502-f0ee-46c9-986c-54ed027807fb"];
		uuid_t uuidbuf;
		[uuid getUUIDBytes:uuidbuf];
		IOBluetoothSDPUUID * uuidBlutooth = [IOBluetoothSDPUUID uuidWithBytes:uuidbuf length:16];
		uuidServices = @[uuidBlutooth];

        NSUUID * uuidZik2 = [[NSUUID alloc] initWithUUIDString:@"8b6814d3-6ce7-4498-9700-9312c1711f63"];
        uuid_t uuidZik2buf;
        [uuidZik2 getUUIDBytes:uuidZik2buf];
        IOBluetoothSDPUUID * uuidZik2Blutooth = [IOBluetoothSDPUUID uuidWithBytes:uuidZik2buf length:16];
        uuidServicesZik2 = @[uuidZik2Blutooth];
});
	NSArray * services = device.services;
	for (IOBluetoothSDPServiceRecord * service in services) {
		if([service matchesUUIDArray:uuidServices]
           || [service matchesUUIDArray:uuidServicesZik2]) {
			IOReturn res = [service getRFCOMMChannelID:&channelId];
			if(res != kIOReturnSuccess)
			{
				NSLog(@"Failed to connect to %@", device.nameOrAddress);
			}
			else {
				NSLog(@"Connected to %@", device.nameOrAddress);
				IOBluetoothRFCOMMChannel * rfCommChannel;
				res = [device openRFCOMMChannelSync:&rfCommChannel withChannelID:channelId delegate:self];
				mRfCommChannel = rfCommChannel;
				NSAssert(res == kIOReturnSuccess, @"Failed to open channel");
				unsigned char buffer[] = {0x00,0x03,0x00};
				state = PSAskingStateInit;
				res = [rfCommChannel writeSync:buffer length:3];
				NSAssert(res == kIOReturnSuccess, @"Failed to send init");
				[device registerForDisconnectNotification:self selector:@selector(disconnected:fromDevice:)];
			}
		}
	}
}
- (void)disconnected:(IOBluetoothUserNotification *)note fromDevice:(IOBluetoothDevice *)device
{
	NSArray * services = device.services;
	for (IOBluetoothSDPServiceRecord * service in services) {
		if([service matchesUUIDArray:uuidServices]) {
			NSLog(@"Disconnected from %@", device.nameOrAddress);
			state = PSAskingStateInit;
			[self updateStatusItem];
		}
	}
}

- (void) sendRequest:(NSString*)request {
	NSString * requestString = request;
	NSMutableData * requestData = [NSMutableData data];
	unsigned char buffer = 0;
	[requestData appendBytes:&buffer length:1];
	buffer = [requestString lengthOfBytesUsingEncoding:NSASCIIStringEncoding]+3;
	[requestData appendBytes:&buffer length:1];
	buffer = 0x80;
	[requestData appendBytes:&buffer length:1];
	[requestData appendData:[requestString dataUsingEncoding:NSASCIIStringEncoding]];
//	IOReturn res = [mRfCommChannel writeSync:(void *)[requestData bytes] length:[requestData length]];
	IOReturn res = [mRfCommChannel writeAsync:(void *)[requestData bytes] length:[requestData length] refcon:NULL];
	NSAssert(res == kIOReturnSuccess, @"Failed to send %@",request);
}

- (void) handleAnswer:(NSXMLDocument*) xmlDocument {
	NSString * path = [[[xmlDocument rootElement] attributeForName:@"path"] stringValue];
//	NSLog(@"answer for path:%@ : %@",path,xmlDocument);
	if([path isEqualToString:@"/api/software/version/get"]) {
		version = [[[[xmlDocument nodesForXPath:@"//software" error:NULL] lastObject] attributeForName:@"version"] stringValue];
        if(version == nil)
            //Zik 2
            version = [[[[xmlDocument nodesForXPath:@"//software" error:NULL] lastObject] attributeForName:@"sip6"] stringValue];
	}
	else if([path isEqualToString:@"/api/bluetooth/friendlyname/get"]) {
		name = [[[[xmlDocument nodesForXPath:@"//bluetooth" error:NULL] lastObject] attributeForName:@"friendlyname"] stringValue];
	}
	else if([path isEqualToString:@"/api/system/battery/get"]) {
		char newBatteryLevel = [[[[[xmlDocument nodesForXPath:@"//battery" error:NULL] lastObject] attributeForName:@"level"] stringValue] intValue];
        if(newBatteryLevel == '\0')
            //Zik 2
            newBatteryLevel = [[[[[xmlDocument nodesForXPath:@"//battery" error:NULL] lastObject] attributeForName:@"percent"] stringValue] intValue];
		batteryCharging = [[[[[xmlDocument nodesForXPath:@"//battery" error:NULL] lastObject] attributeForName:@"state"] stringValue] isEqualToString:@"charging"];
		
		if([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowBatteryNotifications"] && batteryCharging == NO) {
			NSUserNotification * userNotification = nil;
			NSArray * notificationLevels = [[NSUserDefaults standardUserDefaults] arrayForKey:@"BatteryNotificationLevels"];
			NSMutableArray * sortedNotificationLevels = [NSMutableArray array];
			for (NSString * currentLevel in notificationLevels) {
				[sortedNotificationLevels addObject:@([currentLevel intValue])];
			}
			[sortedNotificationLevels sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
				return [obj2 compare:obj1];
			}];
			for (NSString * currentLevel in sortedNotificationLevels) {
				if(batteryLevel > [currentLevel intValue] && newBatteryLevel <= [currentLevel intValue] ) {
					userNotification = [[NSUserNotification alloc] init];
					userNotification.title = NSLocalizedString(@"Parrot Zik Battery Notification", @"");
					userNotification.subtitle = [NSString stringWithFormat:NSLocalizedString(@"%i%% of battery remaining", @""),[currentLevel intValue]];
					break;
				}
			}
			if(!userNotification && [[NSUserDefaults standardUserDefaults] boolForKey:@"ShowBatteryAboutToDieNotifications"] && batteryLevel>=2 && newBatteryLevel<2) {
				userNotification = [[NSUserNotification alloc] init];
				userNotification.title = NSLocalizedString(@"Parrot Zik Battery Low", @"");
				userNotification.subtitle = NSLocalizedString(@"Recharge the battery soon", @"");
			}
			
			if( batteryLevel == 100 &&  newBatteryLevel == 0) {
				userNotification = nil; // Fix wrong notificaiton when disconnecting recharge cable
			}
			
			if( userNotification ) {
				[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:userNotification];
			}
		}
		
		batteryLevel = newBatteryLevel;
		[self updateStatusItem];
	}
	else if([path isEqualToString:@"/api/audio/noise_cancellation/enabled/get"]) {
		noiseCancel = [[[[[xmlDocument nodesForXPath:@"//noise_cancellation" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
	}
	else if([path isEqualToString:@"/api/system/auto_connection/enabled/get"]) {
		autoConnection = [[[[[xmlDocument nodesForXPath:@"//auto_connection" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
	}
	else if([path isEqualToString:@"/api/audio/specific_mode/enabled/get"]) {
		louReedMode = [[[[[xmlDocument nodesForXPath:@"//specific_mode" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
	}
	else if([path isEqualToString:@"/api/audio/sound_effect/enabled/get"]) {
		concertHall = [[[[[xmlDocument nodesForXPath:@"//sound_effect" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
	}
	else {
		NSLog(@"Unknown answer : %@ %@ ",path,xmlDocument);
	}
	[self menuNeedsUpdate:statusItem.menu];
	[statusItem.menu update];
}

- (void)rfcommChannelData:(IOBluetoothRFCOMMChannel*)rfcommChannel data:(void *)dataPointer length:(size_t)dataLength {
	NSData * data = [NSData dataWithBytes:dataPointer length:dataLength];
	UInt16 messageLen = 0;
	[data getBytes:&messageLen range:NSMakeRange(0, 2)];
	unsigned char magic = 0;
	[data getBytes:&magic range:NSMakeRange(2, 1)];
	switch (magic) {
		case 128:
		{
			NSData * xmlData = nil;
			if(data.length > 7)
				xmlData = [data subdataWithRange:NSMakeRange(7, [data length]-7)];
			NSXMLDocument * xmlDocument = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:NULL];
			NSString * rootName = [[xmlDocument rootElement] name];
			if([rootName isEqualToString:@"answer"]) {
				[self handleAnswer:xmlDocument];
			}
			else if([rootName isEqualToString:@"notify"]) {
				NSString * path = [[[xmlDocument rootElement] attributeForName:@"path"] stringValue];
				[self sendRequest:[NSString stringWithFormat:@"GET %@",path]];
			}
			else {
				NSLog(@"Unknown callback %@",xmlDocument);
			}
			break;
		}
		default:
			if( state == PSAskingStateInit) {
				state = PSAskingStateConnected;
				unsigned char buffer[] = {0x00,0x03,0x02};
				BOOL success = [data isEqualToData:[NSData dataWithBytes:buffer length:3]];
				NSAssert(success, @"Recieved unknown init data");
				[self sendRequest:@"GET /api/software/version/get"];
				[self sendRequest:@"GET /api/bluetooth/friendlyname/get"];
				[self sendRequest:@"GET /api/system/battery/get"];
				[self sendRequest:@"GET /api/audio/noise_cancellation/enabled/get"];
				[self sendRequest:@"GET /api/system/auto_connection/enabled/get"];
				[self sendRequest:@"GET /api/audio/specific_mode/enabled/get"];
				[self sendRequest:@"GET /api/audio/sound_effect/enabled/get"];
			}
			break;
	}
}

//- (void)rfcommChannelOpenComplete:(IOBluetoothRFCOMMChannel*)rfcommChannel status:(IOReturn)error {
//	NSLog(@"%s",__FUNCTION__);
//}
//- (void)rfcommChannelClosed:(IOBluetoothRFCOMMChannel*)rfcommChannel {
//	NSLog(@"%s",__FUNCTION__);
//}
//- (void)rfcommChannelControlSignalsChanged:(IOBluetoothRFCOMMChannel*)rfcommChannel {
//	NSLog(@"%s",__FUNCTION__);
//}
//- (void)rfcommChannelFlowControlChanged:(IOBluetoothRFCOMMChannel*)rfcommChannel {
//	NSLog(@"%s",__FUNCTION__);
//}
//- (void)rfcommChannelWriteComplete:(IOBluetoothRFCOMMChannel*)rfcommChannel refcon:(void*)refcon status:(IOReturn)error {
//	NSLog(@"%s",__FUNCTION__);
//}
//- (void)rfcommChannelQueueSpaceAvailable:(IOBluetoothRFCOMMChannel*)rfcommChannel {
//	NSLog(@"%s",__FUNCTION__);
//}

#pragma mark NSTokenField delegate

// For advanced battery settings
- (NSArray *)tokenField:(NSTokenField *)tokenField
	   shouldAddObjects:(NSArray *)tokens
				atIndex:(NSUInteger)index {
	NSMutableArray * validatedTokens = [NSMutableArray array];
	NSArray * notificationLevels = [[NSUserDefaults standardUserDefaults] arrayForKey:@"BatteryNotificationLevels"];
	for (NSString * currentToken in tokens) {
		int currentIntValue = [currentToken intValue];
		if(currentIntValue <= 2 || currentIntValue > 99) {
			NSBeep();
			continue;
		}
		NSString * newValue = [NSString stringWithFormat:@"%i%%",currentIntValue];
		if([notificationLevels containsObject:newValue]){
			NSBeep();
			continue;
		}
		if([validatedTokens containsObject:newValue]){
			NSBeep();
			continue;
		}
		[validatedTokens addObject:newValue];
	}
	return validatedTokens;
}

#pragma mark Actions
- (IBAction)toogleBatteryNotifications:(id)sender {
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	[userDefaults setBool:![userDefaults boolForKey:@"ShowBatteryNotifications"] forKey:@"ShowBatteryNotifications"];
}

- (IBAction)toggleNoiseCancellation:(id)sender {
	[self sendRequest:[NSString stringWithFormat:@"SET /api/audio/noise_cancellation/enabled/set?arg=%@",noiseCancel?@"false":@"true"]];
	[self sendRequest:@"GET /api/audio/noise_cancellation/enabled/get"];
}

- (IBAction)toggleAutoConnect:(id)sender {
	[self sendRequest:[NSString stringWithFormat:@"SET /api/system/auto_connection/enabled/set?arg=%@",autoConnection?@"false":@"true"]];
	[self sendRequest:@"GET /api/system/auto_connection/enabled/get"];
}

- (IBAction)toggleLouReed:(id)sender {
	if(!louReedMode && concertHall) {
		[self toggleConcertHall:sender];
	}
	[self sendRequest:[NSString stringWithFormat:@"SET /api/audio/specific_mode/enabled/set?arg=%@",louReedMode?@"false":@"true"]];
	[self sendRequest:@"GET /api/audio/specific_mode/enabled/get"];
}

- (IBAction)toggleConcertHall:(id)sender {
	if(louReedMode && !concertHall) {
		[self toggleLouReed:sender];
	}
	[self sendRequest:[NSString stringWithFormat:@"SET /api/audio/sound_effect/enabled/set?arg=%@",concertHall?@"false":@"true"]];
	[self sendRequest:@"GET /api/audio/sound_effect/enabled/get"];
}

- (IBAction)about:(id)sender {
	[NSApp orderFrontStandardAboutPanel:sender];
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)showAdvancedBatteryOptions:(id)sender {
	[self.advancedBatteryWindow makeKeyAndOrderFront:sender];
	[NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)showBatteryIconOnly:(id)sender {
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ShowBatteryPercentage"];
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ShowBatteryIcon"];
	[self updateStatusItem];
}

- (IBAction)showBatteryIconAndText:(id)sender {
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ShowBatteryPercentage"];
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ShowBatteryIcon"];
	[self updateStatusItem];
}

- (IBAction)showBatteryTextOnly:(id)sender {
	[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"ShowBatteryPercentage"];
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ShowBatteryIcon"];
	[self updateStatusItem];
}

- (IBAction)hideWhenDisconnected:(id)sender {
	NSAlert * alert = [[NSAlert alloc] init];
	alert.messageText = NSLocalizedString(@"Parrot Status will be hidden when device is disconnected", @"");
	alert.informativeText = NSLocalizedString(@"To show menu when the device is disconnected, you will have to launch the app again.", @"");
	[alert addButtonWithTitle:NSLocalizedString(@"Hide", @"")];
	[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
	NSModalResponse response = [alert runModal];
	if(response == NSAlertFirstButtonReturn) {
		[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HiddenWhenDisconnected"];
		[self updateStatusItem];
	}
}

- (IBAction)showWhenDisconnected:(id)sender {
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"HiddenWhenDisconnected"];
	[self updateStatusItem];
}

@end


@implementation AppDelegate(SharedFileListExample)
// See https://github.com/justin/Shared-File-List-Example/blob/master/Controller.m

/*
 
 The MIT License
 
 Copyright (c) 2010 Justin Williams, Second Gear
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */


- (void)enableLoginItemWithLoginItemsReference:(LSSharedFileListRef )theLoginItemsRefs forPath:(NSString *)appPath {
	// We call LSSharedFileListInsertItemURL to insert the item at the bottom of Login Items list.
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
	LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(theLoginItemsRefs, kLSSharedFileListItemLast, NULL, NULL, url, NULL, NULL);
	if (item)
		CFRelease(item);
		}

- (void)disableLoginItemWithLoginItemsReference:(LSSharedFileListRef )theLoginItemsRefs forPath:(NSString *)appPath {
	UInt32 seedValue;
	CFURLRef thePath = NULL;
	// We're going to grab the contents of the shared file list (LSSharedFileListItemRef objects)
	// and pop it in an array so we can iterate through it to find our item.
	CFArrayRef loginItemsArray = LSSharedFileListCopySnapshot(theLoginItemsRefs, &seedValue);
	for (id item in (__bridge NSArray *)loginItemsArray) {
		LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;
		if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &thePath, NULL) == noErr) {
			if ([[(__bridge NSURL *)thePath path] hasPrefix:appPath]) {
				LSSharedFileListItemRemove(theLoginItemsRefs, itemRef); // Deleting the item
			}
			// Docs for LSSharedFileListItemResolve say we're responsible
			// for releasing the CFURLRef that is returned
			if (thePath != NULL) CFRelease(thePath);
		}
	}
	if (loginItemsArray != NULL) CFRelease(loginItemsArray);
		}

- (BOOL)loginItemExistsWithLoginItemReference:(LSSharedFileListRef)theLoginItemsRefs forPath:(NSString *)appPath {
	BOOL found = NO;
	UInt32 seedValue;
	CFURLRef thePath = NULL;
	
	// We're going to grab the contents of the shared file list (LSSharedFileListItemRef objects)
	// and pop it in an array so we can iterate through it to find our item.
	CFArrayRef loginItemsArray = LSSharedFileListCopySnapshot(theLoginItemsRefs, &seedValue);
	for (id item in (__bridge NSArray *)loginItemsArray) {
		LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;
		if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &thePath, NULL) == noErr) {
			if ([[(__bridge NSURL *)thePath path] hasPrefix:appPath]) {
				found = YES;
				break;
			}
			// Docs for LSSharedFileListItemResolve say we're responsible
			// for releasing the CFURLRef that is returned
			if (thePath != NULL) CFRelease(thePath);
		}
	}
	if (loginItemsArray != NULL) CFRelease(loginItemsArray);
		
		return found;
}

@end
