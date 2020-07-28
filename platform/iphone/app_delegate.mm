/*************************************************************************/
/*  app_delegate.mm                                                      */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2020 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2020 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#import "app_delegate.h"
#include "core/project_settings.h"
#include "drivers/coreaudio/audio_driver_coreaudio.h"
#import "godot_view.h"
#include "main/main.h"
#include "os_iphone.h"
#import "view_controller.h"

#import <AudioToolbox/AudioServices.h>

#define kRenderingFrequency 60

extern int gargc;
extern char **gargv;

extern int iphone_main(int, char **, String);
extern void iphone_finish();

@implementation AppDelegate

static ViewController *mainViewController = nil;

+ (ViewController *)viewController {
	return mainViewController;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	// TODO: might be required to make an early return, so app wouldn't crash because of timeout.
	// TODO: logo screen is not displayed while shaders are compiling
	// DummyViewController(Splash/LoadingViewController) -> setup -> GodotViewController

	CGRect windowBounds = [[UIScreen mainScreen] bounds];

	// Create a full-screen window
	self.window = [[[UIWindow alloc] initWithFrame:windowBounds] autorelease];

	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];

	int err = iphone_main(gargc, gargv, String::utf8([documentsDirectory UTF8String]));

	if (err != 0) {
		// bail, things did not go very well for us, should probably output a message on screen with our error code...
		exit(0);
		return NO;
	};

	ViewController *viewController = [[ViewController alloc] init];
	viewController.godotView.useCADisplayLink = bool(GLOBAL_DEF("display.iOS/use_cadisplaylink", true)) ? YES : NO;
	viewController.godotView.renderingInterval = 1.0 / kRenderingFrequency;

	self.window.rootViewController = viewController;

	// Show the window
	[self.window makeKeyAndVisible];

	[[NSNotificationCenter defaultCenter]
			addObserver:self
			   selector:@selector(onAudioInterruption:)
				   name:AVAudioSessionInterruptionNotification
				 object:[AVAudioSession sharedInstance]];

	mainViewController = viewController;

	if (GLOBAL_GET("audio/raw_input_stream"))
	{
		NSError *modeError;

		// This mode minimizes the amount of system-supplied signal processing to input and output signals
		if ([[AVAudioSession sharedInstance] setMode:AVAudioSessionModeMeasurement error:&modeError] == NO)
		{
			NSLog(@"Audio mode error: %zd" + modeError.code);
		}
	}

	NSError *categoryError;

	// Prevent to stop music in another background app
	if ([[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:&categoryError] == NO)
	{
		NSLog(@"Audio category error: %zd" + categoryError.code);
	}

	return YES;
};

- (void)onAudioInterruption:(NSNotification *)notification {
	if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
		if ([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeBegan]]) {
			NSLog(@"Audio interruption began");
			OSIPhone::get_singleton()->on_focus_out();
		} else if ([[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] isEqualToNumber:[NSNumber numberWithInt:AVAudioSessionInterruptionTypeEnded]]) {
			NSLog(@"Audio interruption ended");
			OSIPhone::get_singleton()->on_focus_in();
		}
	}
};

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
	if (OS::get_singleton()->get_main_loop()) {
		OS::get_singleton()->get_main_loop()->notification(MainLoop::NOTIFICATION_OS_MEMORY_WARNING);
	}
};

- (void)applicationWillTerminate:(UIApplication *)application {
	iphone_finish();
};

// When application goes to background (e.g. user switches to another app or presses Home),
// then applicationWillResignActive -> applicationDidEnterBackground are called.
// When user opens the inactive app again,
// applicationWillEnterForeground -> applicationDidBecomeActive are called.

// There are cases when applicationWillResignActive -> applicationDidBecomeActive
// sequence is called without the app going to background. For example, that happens
// if you open the app list without switching to another app or open/close the
// notification panel by swiping from the upper part of the screen.

- (void)applicationWillResignActive:(UIApplication *)application {
	OSIPhone::get_singleton()->on_focus_out();
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
	OSIPhone::get_singleton()->on_focus_in();
}

- (void)dealloc {
	self.window = nil;
	[super dealloc];
}

@end
