//
//  AppDelegate.m
//  Parrot Status
//
//  Created by Vincent Le Normand on 29/10/2014.
//  Copyright (c) 2014 Vincent Le Normand. All rights reserved.
//

#import "AppDelegate.h"
#import <IOBluetooth/IOBluetooth.h>

typedef NS_ENUM(NSInteger, PSState) {
	PSAskingStateInit,
	PSAskingStateConnected,
};

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
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
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// Insert code here to initialize your application
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
	[self updateImage];
	statusItem.highlightMode = YES;
	NSMenu * myMenu = [[NSMenu alloc] initWithTitle:@"Test"];
	myMenu.delegate = self;
//	[myMenu addItemWithTitle:@"test" action:NULL keyEquivalent:@""];
	statusItem.menu = myMenu;
	
	[IOBluetoothDevice registerForConnectNotifications:self selector:@selector(connected:fromDevice:)];
}

- (void) updateImage {
	statusItem.image = [NSImage imageWithSize:NSMakeSize(43, 43) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
		if( state == PSAskingStateConnected) {
			[[NSColor blackColor] set];
		}
		else {
			[[NSColor colorWithDeviceWhite:0.0 alpha:0.5] set];
		}
		NSBezierPath  * headset = [NSBezierPath bezierPath];
		[headset moveToPoint:NSMakePoint(10.5, 19.5)];
		[headset curveToPoint:NSMakePoint(18.5, 19.5) controlPoint1:NSMakePoint(13.5, 31.5) controlPoint2:NSMakePoint(15.5, 31.5)];
		[headset appendBezierPathWithOvalInRect:NSMakeRect(10.5, 15.5, 2, 6)];
		[headset appendBezierPathWithOvalInRect:NSMakeRect(16.5, 15.5, 2, 6)];
		[headset setLineWidth:2.5];
		[headset stroke];
		if( state == PSAskingStateConnected) {
			[[NSColor blackColor] set];
			NSRect batteryRect = NSMakeRect(20.5,14.5,6,13);
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

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}

- (void)menuNeedsUpdate:(NSMenu*)menu {
	[menu removeAllItems];
	if( state == PSAskingStateConnected) {
		[menu addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Conencted to %@", @""),name] action:@selector(test) keyEquivalent:@""];
		[menu addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Version %@", @""),version] action:@selector(test) keyEquivalent:@""];
		[menu addItemWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Battery level: %i%% %@", @""),batteryLevel,(batteryCharging?NSLocalizedString(@"- charging", @""):@"")] action:@selector(test) keyEquivalent:@""];
		[menu addItem:[NSMenuItem separatorItem]];
		[[menu addItemWithTitle:NSLocalizedString(@"Noise Cancellation", @"") action:@selector(toogleNoiseCancellation:) keyEquivalent:@""] setState:noiseCancel?NSOnState:NSOffState];
		[[menu addItemWithTitle:NSLocalizedString(@"Auto connection", @"") action:@selector(toogleAutoConnect:) keyEquivalent:@""] setState:autoConnection?NSOnState:NSOffState];
		[[menu addItemWithTitle:NSLocalizedString(@"Lou Reed Mode", @"") action:@selector(toogleLouReed:) keyEquivalent:@""] setState:louReedMode?NSOnState:NSOffState];
		[[menu addItemWithTitle:NSLocalizedString(@"Concert Hall Mode", @"") action:@selector(toogleConcertHall:) keyEquivalent:@""] setState:concertHall?NSOnState:NSOffState];
	}
	else {
		[menu addItemWithTitle:NSLocalizedString(@"Not connected",@"") action:@selector(test) keyEquivalent:@""];
	}
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:NSLocalizedString(@"About", @"") action:@selector(about:) keyEquivalent:@""];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItemWithTitle:NSLocalizedString(@"Quit", @"") action:@selector(terminate:) keyEquivalent:@""];
}

#pragma mark -
#pragma mark IOBluetoothUserNotification

static NSArray * uuidServices = nil;
- (void)connected:(IOBluetoothUserNotification *)note fromDevice:(IOBluetoothDevice *)device
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSUUID * uuid = [[NSUUID alloc] initWithUUIDString:@"0ef0f502-f0ee-46c9-986c-54ed027807fb"];
		uuid_t uuidbuf;
		[uuid getUUIDBytes:uuidbuf];
		IOBluetoothSDPUUID * uuidBlutooth = [IOBluetoothSDPUUID uuidWithBytes:uuidbuf length:16];
		uuidServices = @[uuidBlutooth];
	});
	NSArray * services = device.services;
	for (IOBluetoothSDPServiceRecord * service in services) {
		if([service matchesUUIDArray:uuidServices]) {
			IOReturn res = [service getRFCOMMChannelID:&channelId];
			if(res != kIOReturnSuccess)
			{
				NSLog(@"Failed to connect to %@", device.nameOrAddress);
			}
			else {
				NSLog(@"Connected %@", device.nameOrAddress);
				IOBluetoothRFCOMMChannel * rfCommChannel;
				res = [device openRFCOMMChannelSync:&rfCommChannel withChannelID:channelId delegate:self];
				mRfCommChannel = rfCommChannel;
				NSAssert(res == kIOReturnSuccess, @"Failed to open chanel");
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
			[self updateImage];
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
	}
	else if([path isEqualToString:@"/api/bluetooth/friendlyname/get"]) {
		name = [[[[xmlDocument nodesForXPath:@"//bluetooth" error:NULL] lastObject] attributeForName:@"friendlyname"] stringValue];
	}
	else if([path isEqualToString:@"/api/system/battery/get"]) {
		batteryLevel = [[[[[xmlDocument nodesForXPath:@"//battery" error:NULL] lastObject] attributeForName:@"level"] stringValue] intValue];
		batteryCharging = [[[[[xmlDocument nodesForXPath:@"//battery" error:NULL] lastObject] attributeForName:@"state"] stringValue] isEqualToString:@"charging"];
		NSLog(@"Battery state:%@",[[[[xmlDocument nodesForXPath:@"//battery" error:NULL] lastObject] attributeForName:@"state"] stringValue]);
		[self updateImage];
	}
	else if([path isEqualToString:@"/api/audio/noise_cancellation/enabled/get"]) {
		noiseCancel = [[[[[xmlDocument nodesForXPath:@"//noise_cancellation" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
		[self updateImage];
	}
	else if([path isEqualToString:@"/api/system/auto_connection/enabled/get"]) {
		autoConnection = [[[[[xmlDocument nodesForXPath:@"//auto_connection" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
		[self updateImage];
	}
	else if([path isEqualToString:@"/api/audio/specific_mode/enabled/get"]) {
		louReedMode = [[[[[xmlDocument nodesForXPath:@"//specific_mode" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
		[self updateImage];
	}
	else if([path isEqualToString:@"/api/audio/sound_effect/enabled/get"]) {
		concertHall = [[[[[xmlDocument nodesForXPath:@"//sound_effect" error:NULL] lastObject] attributeForName:@"enabled"] stringValue] isEqualToString:@"true"];
		[self updateImage];
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
				NSAssert([data isEqualToData:[NSData dataWithBytes:buffer length:3]], @"Recieved unknown init data");
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

#pragma mark Actions
- (IBAction)toogleNoiseCancellation:(id)sender {
	[self sendRequest:[NSString stringWithFormat:@"SET /api/audio/noise_cancellation/enabled/set?arg=%@",noiseCancel?@"false":@"true"]];
	[self sendRequest:@"GET /api/audio/noise_cancellation/enabled/get"];
}

- (IBAction)toogleAutoConnect:(id)sender {
	[self sendRequest:[NSString stringWithFormat:@"SET /api/system/auto_connection/enabled/set?arg=%@",autoConnection?@"false":@"true"]];
	[self sendRequest:@"GET /api/system/auto_connection/enabled/get"];
}

- (IBAction)toogleLouReed:(id)sender {
	if(!louReedMode && concertHall) {
		[self toogleConcertHall:sender];
	}
	[self sendRequest:[NSString stringWithFormat:@"SET /api/audio/specific_mode/enabled/set?arg=%@",louReedMode?@"false":@"true"]];
	[self sendRequest:@"GET /api/audio/specific_mode/enabled/get"];
}

- (IBAction)toogleConcertHall:(id)sender {
	if(louReedMode && !concertHall) {
		[self toogleLouReed:sender];
	}
	[self sendRequest:[NSString stringWithFormat:@"SET /api/audio/sound_effect/enabled/set?arg=%@",concertHall?@"false":@"true"]];
	[self sendRequest:@"GET /api/audio/sound_effect/enabled/get"];
}

- (IBAction)about:(id)sender {
	[NSApp orderFrontStandardAboutPanel:sender];
	[NSApp activateIgnoringOtherApps:YES];
}


@end
