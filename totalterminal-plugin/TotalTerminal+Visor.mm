#import <Quartz/Quartz.h>

#import <terminal/TTWindowController.h>
#import <terminal/TTWindow.h>
#import <terminal/TTProfileManager.h>
#import <terminal/TTTabController.h>
#import <terminal/TTPane.h>
#import <terminal/TTView.h>
#import <terminal/TTApplication.h>

#import "CGSPrivate.h"
#import "QSBKeyMap.h"
#import "GTMHotKeyTextField.h"

#import "TotalTerminal+Visor.h"
#import "TotalTerminal+Shortcuts.h"

#undef PROJECT
#define PROJECT Visor

#define SLIDE_EASING(x) sin(M_PI_2 * (x))
#define ALPHA_EASING(x) (1.0f - (x))
#define SLIDE_DIRECTION(d, x) (d ? (x) : (1.0f - (x)))
#define ALPHA_DIRECTION(d, x) (d ? (1.0f - (x)) : (x))

@interface NSEvent (TotalTerminal)
-(NSUInteger) qsbModifierFlags;
@end

@implementation NSEvent (TotalTerminal)

-(NSUInteger) qsbModifierFlags {
  NSUInteger flags = ([self modifierFlags] & NSDeviceIndependentModifierFlagsMask);

  // Ignore caps lock if it's set http://b/issue?id=637380
  if (flags & NSAlphaShiftKeyMask) {
    flags -= NSAlphaShiftKeyMask;                                   // Ignore numeric lock if it's set http://b/issue?id=637380
  }
  if (flags & NSNumericPadKeyMask)
    flags -= NSNumericPadKeyMask;
  return flags;
}

@end

@interface TotalTerminal (VisorPrivate)
-(void) applyVisorPositioning;
@end

@implementation VisorScreenTransformer

+(Class) transformedValueClass {
  LOG(@"transformedValueClass");
  return [NSNumber class];
}

+(BOOL) allowsReverseTransformation {
  LOG(@"allowsReverseTransformation");

  return YES;
}

-(id) transformedValue:(id)value {
  LOG(@"transformedValue %@", value);
  NSString *screenString;
  int screenCount = [[NSScreen screens] count];
  int screenNumber = [value integerValue];
  if (screenNumber == screenCount ) {
    screenString = @"Current Screen";
  }
  else {
    screenString = [NSString stringWithFormat:@"Screen %d", (int)[value integerValue]];
  }
  return screenString;
}

-(id) reverseTransformedValue:(id)value {
  LOG(@"reverseTransformedValue %@", value);
  int screenCount = [[NSScreen screens] count];
  NSNumber *screenNumber;
  if ([value isEqual: @"Current Screen"] ) {
    screenNumber = [NSNumber numberWithInt:screenCount];
  }
  else {
    screenNumber = [NSNumber numberWithInteger:[[value substringFromIndex:6] integerValue]];
  }
  return screenNumber;
}

@end

@implementation NSWindowController (TotalTerminal)

// ------------------------------------------------------------
// TTWindowController hacks

-(void) SMETHOD (TTWindowController, setCloseDialogExpected):(BOOL)fp8 {
  AUTO_LOGGER();
  if (fp8) {
    TTWindowController* me = (TTWindowController*)self;
    // THIS IS A MEGAHACK! (works for me on Leopard 10.5.6)
    // the problem: beginSheet causes UI to lock for NSBorderlessWindowMask NSWindow which is in "closing mode"
    //
    // this hack tries to open sheet before window starts its closing procedure
    // we expect that setCloseDialogExpected is called by Terminal.app once BEFORE window gets into "closing mode"
    // in this case we are able to open sheet before window starts closing and this works even for window with NSBorderlessWindowMask
    // it works like a magic, took me few hours to figure out this random stuff
    [[TotalTerminal sharedInstance] showVisor:false];
    [me displayWindowCloseSheet:1];
  }
}

-(NSRect) window:(NSWindow*)window willPositionSheet:(NSWindow*)sheet usingRect:(NSRect)rect {
  return rect;
}

-(NSRect) SMETHOD (TTWindowController, window):(NSWindow*)window willPositionSheet:(NSWindow*)sheet usingRect:(NSRect)rect {
  AUTO_LOGGER();
  [TotalTerminal sharedInstance];
  return rect;
}

-(id) SMETHOD (TTWindowController, getVisorProfileOrTheDefaultOne) {
  id visorProfile = [TotalTerminal getVisorProfile];

  if (visorProfile) {
    return visorProfile;
  } else {
    id profileManager = [NSClassFromString (@"TTProfileManager")sharedProfileManager];
    return [profileManager defaultProfile];
  }
}

-(id) SMETHOD (TTWindowController, forceVisorProfileIfVisoredWindow) {
  AUTO_LOGGER();
  id res = nil;
  TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
  BOOL isVisorWindow = [totalTerminal isVisorWindow:[self window]];

  if (isVisorWindow) {
    LOG(@"  in visor window ... so apply visor profile");
    res = [self SMETHOD (TTWindowController, getVisorProfileOrTheDefaultOne)];
  }
  return res;
}

// swizzled function for original TTWindowController::newTabWithProfile
// this seems to be a good point to intercept new tab creation
// responsible for opening all tabs in Visored window with Visor profile (regardless of "default profile" setting)
-(id) SMETHOD (TTWindowController, newTabWithProfile):(id)arg1 {
  id profile = [self SMETHOD (TTWindowController, forceVisorProfileIfVisoredWindow)]; // returns nil if not Visor-ed window

  AUTO_LOGGERF(@"profile=%@", profile);
  if (profile) {
    arg1 = profile;
    ScopedNSDisableScreenUpdatesWithDelay disabler(0, __FUNCTION__); // this is needed to prevent visual switch when calling resetVisorWindowSize followed by applyVisorPositioning
    [[TotalTerminal sharedInstance] resetVisorWindowSize]; // see https://github.com/binaryage/totalterminal/issues/56
  }
  id tab = [self SMETHOD (TTWindowController, newTabWithProfile):arg1];
  if (profile) {
    [[TotalTerminal sharedInstance] applyVisorPositioning];
  }
  return tab;
}

// this is variant of the ^^^
// this seems to be an alternative point to intercept new tab creation
-(id) SMETHOD (TTWindowController, newTabWithProfile):(id)arg1 command:(id)arg2 runAsShell:(BOOL)arg3 {
  id profile = [self SMETHOD (TTWindowController, forceVisorProfileIfVisoredWindow)]; // returns nil if not Visor-ed window

  AUTO_LOGGERF(@"profile=%@", profile);
  if (profile) {
    arg1 = profile;
    ScopedNSDisableScreenUpdatesWithDelay disabler(0, __FUNCTION__); // this is needed to prevent visual switch when calling resetVisorWindowSize followed by applyVisorPositioning
    [[TotalTerminal sharedInstance] resetVisorWindowSize]; // see https://github.com/binaryage/totalterminal/issues/56
  }
  id tab = [self SMETHOD (TTWindowController, newTabWithProfile):arg1 command:arg2 runAsShell:arg3];
  if (profile) {
    [[TotalTerminal sharedInstance] applyVisorPositioning];
  }
  return tab;
}

// LION: this is variant of the ^^^
-(id) SMETHOD (TTWindowController, newTabWithProfile):(id)arg1 customFont:(id)arg2 command:(id)arg3 runAsShell:(BOOL)arg4 restorable:(BOOL)arg5 workingDirectory:(id)arg6 sessionClass:(id)arg7
 restoreSession                                      :(id)arg8 {
  id profile = [self SMETHOD (TTWindowController, forceVisorProfileIfVisoredWindow)]; // returns nil if not Visor-ed window

  AUTO_LOGGERF(@"profile=%@", profile);
  if (profile) {
    arg1 = profile;
    ScopedNSDisableScreenUpdatesWithDelay disabler(0, __FUNCTION__); // this is needed to prevent visual switch when calling resetVisorWindowSize followed by applyVisorPositioning
    [[TotalTerminal sharedInstance] resetVisorWindowSize]; // see https://github.com/binaryage/totalterminal/issues/56
  }
  id tab = [self SMETHOD (TTWindowController, newTabWithProfile):arg1 customFont:arg2 command:arg3 runAsShell:arg4 restorable:arg5 workingDirectory:arg6 sessionClass:arg7 restoreSession:arg8];
  if (profile) {
    [[TotalTerminal sharedInstance] applyVisorPositioning];
  }
  return tab;
}

// Mountain Lion renaming since v304
-(id) SMETHOD (TTWindowController, makeTabWithProfile):(id)arg1 {
  id profile = [self SMETHOD (TTWindowController, forceVisorProfileIfVisoredWindow)]; // returns nil if not Visor-ed window

  AUTO_LOGGERF(@"profile=%@", profile);
  if (profile) {
    arg1 = profile;
    ScopedNSDisableScreenUpdatesWithDelay disabler(0, __FUNCTION__); // this is needed to prevent visual switch when calling resetVisorWindowSize followed by applyVisorPositioning
    [[TotalTerminal sharedInstance] resetVisorWindowSize]; // see https://github.com/binaryage/totalterminal/issues/56
  }
  id tab = [self SMETHOD (TTWindowController, makeTabWithProfile):arg1];
  if (profile) {
    [[TotalTerminal sharedInstance] applyVisorPositioning];
  }
  return tab;
}

-(id) SMETHOD (TTWindowController,
               makeTabWithProfile):(id)arg1 customFont:(id)arg2 command:(id)arg3 runAsShell:(BOOL)arg4 restorable:(BOOL)arg5 workingDirectory:(id)arg6 sessionClass:(id)arg7 restoreSession:(id)arg8 {
  id profile = [self SMETHOD (TTWindowController, forceVisorProfileIfVisoredWindow)]; // returns nil if not Visor-ed window

  AUTO_LOGGERF(@"profile=%@", profile);
  if (profile) {
    arg1 = profile;
    ScopedNSDisableScreenUpdatesWithDelay disabler(0, __FUNCTION__); // this is needed to prevent visual switch when calling resetVisorWindowSize followed by applyVisorPositioning
    [[TotalTerminal sharedInstance] resetVisorWindowSize]; // see https://github.com/binaryage/totalterminal/issues/56
  }

  id tab = [self SMETHOD (TTWindowController, makeTabWithProfile):arg1 customFont:arg2 command:arg3 runAsShell:arg4 restorable:arg5 workingDirectory:arg6 sessionClass:arg7 restoreSession:arg8];
  if (profile) {
    [[TotalTerminal sharedInstance] applyVisorPositioning];
  }
  return tab;
}

// The following TabView methods fill out support for making and closing tabs
-(void) SMETHOD (TTWindowController, tabView):(id)arg1 didCloseTabViewItem:(id)arg2 {
  AUTO_LOGGER();
  [self SMETHOD (TTWindowController, tabView):arg1 didCloseTabViewItem:arg2];
  if ([(TTWindowController*) self numberOfTabs] == 1) {
    TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
    BOOL isVisorWindow = [totalTerminal isVisorWindow:[self window]];
    if (isVisorWindow) [totalTerminal applyVisorPositioning];
  }
}

@end

@implementation NSObject (TotalTerminal)

// Both [TTWindowController close/splitActivePane:] and [TTPane close/splitPressed:] call these methods
-(void) SMETHOD (TTTabController, closePane):(id)arg1 {
  AUTO_LOGGER();
  [(TTTabController*) self SMETHOD(TTTabController, closePane):arg1];
  TTWindowController* winc = [(TTTabController*) self windowController];
  TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
  if ([totalTerminal isVisorWindow:[winc window]]) {
    [totalTerminal applyVisorPositioning];
  }
}

-(void) SMETHOD (TTTabController, splitPane):(id)arg1 {
  AUTO_LOGGER();
  [(TTTabController*) self SMETHOD(TTTabController, splitPane):arg1];
  TTWindowController* winc = [(TTTabController*) self windowController];
  TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
  if ([totalTerminal isVisorWindow:[winc window]]) {
    [totalTerminal applyVisorPositioning];
  }
}

@end

@implementation NSApplication (TotalTerminal)

-(void) SMETHOD (TTApplication, sendEvent):(NSEvent*)theEvent {
  NSUInteger type = [theEvent type];

  if (type == NSFlagsChanged) {
    TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
    [totalTerminal modifiersChangedWhileActive:theEvent];
  } else if ((type == NSKeyDown) || (type == NSKeyUp)) {
    TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
    [totalTerminal keysChangedWhileActive:theEvent];
  } else if (type == NSMouseMoved) {
    // TODO review this: it caused background intialization even if Quartz background was disabled in the preferences
    // => https://github.com/darwin/visor/issues/102#issuecomment-1508598
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorUseBackgroundAnimation"]) {
      [[[TotalTerminal sharedInstance] background] sendEvent:theEvent];
    }
  }
  [self SMETHOD (TTApplication, sendEvent):theEvent];
}

@end

@implementation NSWindow (TotalTerminal)

-(id) SMETHOD (TTWindow, initWithContentRect):(NSRect)contentRect styleMask:(NSUInteger)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag {
  AUTO_LOGGER();
  TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
  BOOL shouldBeVisorized = ![totalTerminal status];
  if (shouldBeVisorized) {
    aStyle = NSBorderlessWindowMask;
    bufferingType = NSBackingStoreBuffered;
  }
  TTWindow* window = [self SMETHOD (TTWindow, initWithContentRect):contentRect styleMask:aStyle backing:bufferingType defer:flag];

  if (shouldBeVisorized) {
    [totalTerminal adoptTerminal:window];
  }
  return window;
}

-(BOOL) SMETHOD (TTWindow, canBecomeKeyWindow) {
  BOOL canBecomeKeyWindow = YES;

  TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];

  if ([[totalTerminal window] isEqual:self] && [totalTerminal isHidden]) {
    canBecomeKeyWindow = NO;
  }

  return canBecomeKeyWindow;
}

-(BOOL) SMETHOD (TTWindow, canBecomeMainWindow) {
  BOOL canBecomeMainWindow = YES;

  TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];

  if ([[totalTerminal window] isEqual:self] && [totalTerminal isHidden]) {
    canBecomeMainWindow = NO;
  }

  return canBecomeMainWindow;
}

-(void) SMETHOD (TTWindow, performClose):(id)sender {
  AUTO_LOGGERF(@"sender=%@", sender);
  // close Visor window hard way, for some reason performClose fails for Visor window under Lion
  TotalTerminal* totalTerminal = [TotalTerminal sharedInstance];
  if ([[totalTerminal window] isEqual:self]) {
    // this check is needed for case when there are running shell commands and Terminal shows closing prompt dialog
    if ([[self windowController] windowShouldClose:sender]) {
      [self close];
      return;
    }
  }
  return [self SMETHOD (TTWindow, performClose):sender];
}

@end

@implementation TotalTerminal (Visor)

-(NSWindow*) window {
  return _window;
}

-(void) setWindow:(NSWindow*)inWindow {
  AUTO_LOGGERF(@"window=%@", inWindow);
  NSNotificationCenter* dnc = [NSNotificationCenter defaultCenter];

  [dnc removeObserver:self name:NSWindowDidBecomeKeyNotification object:_window];
  [dnc removeObserver:self name:NSWindowDidResignKeyNotification object:_window];
  [dnc removeObserver:self name:NSWindowDidBecomeMainNotification object:_window];
  [dnc removeObserver:self name:NSWindowDidResignMainNotification object:_window];
  [dnc removeObserver:self name:NSWindowWillCloseNotification object:_window];
  [dnc removeObserver:self name:NSApplicationDidChangeScreenParametersNotification object:nil];

  _window = inWindow;

  if (_window) {
    [dnc addObserver:self selector:@selector(becomeKey:) name:NSWindowDidBecomeKeyNotification object:_window];
    [dnc addObserver:self selector:@selector(resignKey:) name:NSWindowDidResignKeyNotification object:_window];
    [dnc addObserver:self selector:@selector(becomeMain:) name:NSWindowDidBecomeMainNotification object:_window];
    [dnc addObserver:self selector:@selector(resignMain:) name:NSWindowDidResignMainNotification object:_window];
    [dnc addObserver:self selector:@selector(willClose:) name:NSWindowWillCloseNotification object:_window];
    [dnc addObserver:self selector:@selector(applicationDidChangeScreenScreenParameters:) name:NSApplicationDidChangeScreenParametersNotification object:nil];

    [self updateHotKeyRegistration];
    [self updateEscapeHotKeyRegistration];
    [self updateFullScreenHotKeyRegistration];
  } else {
    _isHidden = YES;
    // properly unregister hotkey registrations (issue #53)
    [self unregisterEscapeHotKeyRegistration];
    [self unregisterFullScreenHotKeyRegistration];
    [self unregisterHotKeyRegistration];
  }
}

// this is called by TTAplication::sendEvent
-(NSWindow*) background {
  return _background;
}

-(void) createBackground {
  if (_background) {
    [self destroyBackground];
  }

  _background = [[[NSWindow class] alloc] initWithContentRect:NSZeroRect styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
  [_background orderFront:nil];
  [_background setLevel:NSMainMenuWindowLevel - 2];
  [_background setIgnoresMouseEvents:YES];
  [_background setOpaque:NO];
  [_background setHasShadow:NO];
  [_background setReleasedWhenClosed:YES];
  [_background setLevel:NSFloatingWindowLevel];
  [_background setHasShadow:NO];

  QCView* content = [[QCView alloc] init];

  [content setEventForwardingMask:NSMouseMovedMask];
  [_background setContentView:content];
  [_background makeFirstResponder:content];

  NSString* path = [[NSUserDefaults standardUserDefaults] stringForKey:@"TotalTerminalVisorBackgroundAnimationFile"];
  path = [path stringByStandardizingPath];

  NSFileManager* fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:path]) {
    NSLog(@"animation does not exist: %@", path);
    path = nil;
  }
  if (!path) {
    path = [[NSBundle bundleForClass:[self class]] pathForResource:@"Visor" ofType:@"qtz"];
  }
  [content loadCompositionFromFile:path];
  [content setMaxRenderingFrameRate:15.0];
  [self updateAnimationAlpha];
  if (_window && ![self isHidden]) {
    [_window orderFront:nil];
  }
}

-(void) destroyBackground {
  if (!_background) {
    return;
  }

  _background = nil;
}

// credit: http://tonyarnold.com/entries/fixing-an-annoying-expose-bug-with-nswindows/
-(void) setupExposeTags:(NSWindow*)win {
  CGSConnection cid;
  CGSWindow wid;
  CGSWindowTag tags[2];
  bool showOnEverySpace = [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorOnEverySpace"];

  wid = [win windowNumber];
  if (wid > 0) {
    cid = _CGSDefaultConnection();
    tags[0] = CGSTagSticky;
    tags[1] = (CGSWindowTag)0;

    if (showOnEverySpace)
      CGSSetWindowTags(cid, wid, tags, 32);
    else
      CGSClearWindowTags(cid, wid, tags, 32);
    tags[0] = (CGSWindowTag)CGSTagExposeFade;
    CGSSetWindowTags(cid, wid, tags, 32);
  }
}

-(float) getVisorAnimationBackgroundAlpha {
  return [[NSUserDefaults standardUserDefaults] integerForKey:@"TotalTerminalVisorBackgroundAnimationOpacity"] / 100.0f;
}

-(void) updateAnimationAlpha {
  if ((_background != nil) && !_isHidden) {
    float bkgAlpha = [self getVisorAnimationBackgroundAlpha];
    [_background setAlphaValue:bkgAlpha];
  }
}

-(float) getVisorProfileBackgroundAlpha {
  id bckColor = _background ? [[[self class] getVisorProfile] valueForKey:@"BackgroundColor"] : nil;

  return bckColor ? [bckColor alphaComponent] : 1.0;
}

-(void) updateVisorWindowSpacesSettings {
  AUTO_LOGGER();
  if (!_window) {
    return;
  }
  bool showOnEverySpace = [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorOnEverySpace"];

  if (showOnEverySpace) {
    [_window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle];
  } else {
    [_window setCollectionBehavior:NSWindowCollectionBehaviorDefault | NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle];
  }
}

-(void) updateVisorWindowLevel {
  AUTO_LOGGER();
  if (!_window) {
    return;
  }
  // https://github.com/binaryage/totalterminal/issues/15
  if (![[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorWindowOnHighLevel"]) {
    [_window setLevel:NSFloatingWindowLevel];
  } else {
    [_window setLevel:NSMainMenuWindowLevel - 1];
  }
}

-(void) adoptTerminal:(id)win {
  LOG(@"adoptTerminal window=%@", win);
  if (_window) {
    LOG(@"adoptTerminal called when old window existed");
  }

  [self setWindow:win];
  [self updateVisorWindowLevel];
  [self updateVisorWindowSpacesSettings];
  [self applyVisorPositioning];

  [self updateStatusMenu];
}

-(void) resetWindowPlacement {
  ScopedNSDisableScreenUpdatesWithDelay disabler(0, __FUNCTION__);   // prevent ocasional flickering

  _lastPosition = nil;
  if (_window) {
    float offset = 1.0f;
    if (_isHidden) {
      offset = 0.0f;
    }
    LOG(@"resetWindowPlacement %@ %f", _window, offset);
    [self applyVisorPositioning];
  } else {
    LOG(@"resetWindowPlacement called for nil window");
  }
}

-(NSString*) position {
  return [[NSUserDefaults standardUserDefaults] stringForKey:@"TotalTerminalVisorPosition"];
}

-(NSScreen*) screen {
  int screenIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"TotalTerminalVisorScreen"];
  int screenCount = [[NSScreen screens] count];
  
  if (screenIndex < screenCount) {
    NSArray* screens = [NSScreen screens];
    
    if (screenIndex >= [screens count]) {
      screenIndex = 0;
    }
    if ([screens count] <= 0) {
      return nil;     // safety net
    }
    return [screens objectAtIndex:screenIndex];
  }
  else {
    return [self getCurrentScreen];
  }
}

-(NSScreen*) getCurrentScreen {
  NSPoint mouseLoc = [NSEvent mouseLocation];
  NSEnumerator *screenEnum = [[NSScreen screens] objectEnumerator];
  NSScreen *currentScreen;
  while ((currentScreen = [screenEnum nextObject]) && !NSMouseInRect(mouseLoc, [currentScreen frame], NO));
  return currentScreen;
}

-(NSRect) menubarFrame:(NSScreen*)screen {
  NSArray* screens = [NSScreen screens];

  if (!screens) return NSZeroRect;

  // menubar is the 0th screen (according to the NSScreen docs)
  NSScreen* menubarScreen = [screens objectAtIndex:0];
  if (screen != menubarScreen) {
    return NSZeroRect;
  }

  NSRect frame = [menubarScreen frame];

  // since the dock can only be on the bottom or the sides, calculate the difference
  // between the frame and the visibleFrame at the top
  NSRect visibleFrame = [menubarScreen visibleFrame];
  NSRect menubarFrame;

  menubarFrame.origin.x = NSMinX(frame);
  menubarFrame.origin.y = NSMaxY(visibleFrame);
  menubarFrame.size.width = NSWidth(frame);
  menubarFrame.size.height = NSMaxY(frame) - NSMaxY(visibleFrame);

  return menubarFrame;
}

// offset==0.0 means window is "hidden" above top screen edge
// offset==1.0 means window is visible right under top screen edge
-(void) placeWindow:(id)win offset:(float)offset {
  NSScreen* screen = [self screen];
  NSRect screenRect = [screen frame];
  NSRect frame = [win frame];
  // respect menubar area
  // see http://code.google.com/p/blacktree-visor/issues/detail?id=19
  NSRect menubar = [self menubarFrame:screen];
  int shift = menubar.size.height - 1;   // -1px to hide bright horizontal line on the edge of chromeless terminal window

  NSString* position = [self position];

  if ([position hasPrefix:@"Top"]) {
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - round(offset * (NSHeight(frame) + shift));
  }
  if ([position hasPrefix:@"Left"]) {
    frame.origin.x = screenRect.origin.x - NSWidth(frame) + round(offset * NSWidth(frame));
  }
  if ([position hasPrefix:@"Right"]) {
    frame.origin.x = screenRect.origin.x + NSWidth(screenRect) - round(offset * NSWidth(frame));
  }
  if ([position hasPrefix:@"Bottom"]) {
    frame.origin.y = screenRect.origin.y - NSHeight(frame) + round(offset * NSHeight(frame));
  }
  [win setFrameOrigin:frame.origin];
  if (_background) {
    [_background setFrame:[_window frame] display:YES];
  }
}

-(void) initializeBackground {
  BOOL useBackground = [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorUseBackgroundAnimation"];

  if (useBackground) {
    [self createBackground];
  } else {
    [self destroyBackground];
  }
  [self applyVisorPositioning];
}

-(void) resetVisorWindowSize {
  AUTO_LOGGER();
  // this block is needed to prevent "<NSSplitView>: the delegate <InterfaceController> was sent -splitView:resizeSubviewsWithOldSize: and left the subview frames in an inconsistent state" type of message
  // http://cocoadev.com/forums/comments.php?DiscussionID=1092
  // this issue is only on Snow Leopard (10.6), because it is newly using NSSplitViews
  NSRect safeFrame;
  safeFrame.origin.x = 0;
  safeFrame.origin.y = 0;
  safeFrame.size.width = 1000;
  safeFrame.size.height = 1000;
  [_window setFrame:safeFrame display:NO];

  // this is a better way of 10.5 path for Terminal on Snow Leopard
  // we may call returnToDefaultSize method on our window's view
  // no more resizing issues like described here: http://github.com/darwin/visor/issues/#issue/1
  TTWindowController* controller = [_window windowController];
  TTTabController* tabc = [controller selectedTabController];
  TTPane* pane = [tabc activePane];
  TTView* view = [pane view];
  [view returnToDefaultSize:self];
}

-(void) applyVisorPositioning {
  AUTO_LOGGER();
  if (!_window) {
    return;     // safety net
  }
  NSDisableScreenUpdates();
  NSScreen* screen = [self screen];
  NSRect screenRect = [screen frame];
  NSString* position = [[NSUserDefaults standardUserDefaults] stringForKey:@"TotalTerminalVisorPosition"];
  if (![position isEqualToString:_lastPosition]) {
    // note: cursor may jump during this operation, so do it only in rare cases when position changes
    // for more info see http://github.com/darwin/visor/issues#issue/27
    [self resetVisorWindowSize];
  }
  _lastPosition = position;
  // respect menubar area
  // see http://code.google.com/p/blacktree-visor/issues/detail?id=19
  NSRect menubar = [self menubarFrame:screen];
  int shift = menubar.size.height - 1;   // -1px to hide bright horizontal line on the edge of chromeless terminal window
  if ([position isEqualToString:@"Top-Stretch"]) {
    NSRect frame = [_window frame];
    frame.size.width = screenRect.size.width;
    frame.origin.x = screenRect.origin.x;
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Top-Left"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x;
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Top-Right"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x + NSWidth(screenRect) - NSWidth(frame);
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Top-Center"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x + (NSWidth(screenRect) - NSWidth(frame)) / 2;
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Left-Stretch"]) {
    NSRect frame = [_window frame];
    frame.size.height = screenRect.size.height - shift;
    frame.origin.x = screenRect.origin.x - NSWidth(frame);
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - NSHeight(frame) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Left-Top"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x - NSWidth(frame);
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - NSHeight(frame) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Left-Bottom"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x - NSWidth(frame);
    frame.origin.y = screenRect.origin.y;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Left-Center"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x - NSWidth(frame);
    frame.origin.y = screenRect.origin.y + (NSHeight(screenRect) - NSHeight(frame)) / 2;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Right-Stretch"]) {
    NSRect frame = [_window frame];
    frame.size.height = screenRect.size.height - shift;
    frame.origin.x = screenRect.origin.x + NSWidth(screenRect);
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - NSHeight(frame) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Right-Top"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x + NSWidth(screenRect);
    frame.origin.y = screenRect.origin.y + NSHeight(screenRect) - NSHeight(frame) - shift;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Right-Bottom"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x + NSWidth(screenRect);
    frame.origin.y = screenRect.origin.y;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Right-Center"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x + NSWidth(screenRect);
    frame.origin.y = screenRect.origin.y + (NSHeight(screenRect) - NSHeight(frame)) / 2;
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Bottom-Stretch"]) {
    NSRect frame = [_window frame];
    frame.size.width = screenRect.size.width;
    frame.origin.x = screenRect.origin.x;
    frame.origin.y = screenRect.origin.y - NSHeight(frame);
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Bottom-Left"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x;
    frame.origin.y = screenRect.origin.y - NSHeight(frame);
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Bottom-Right"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x + NSWidth(screenRect) - NSWidth(frame);
    frame.origin.y = screenRect.origin.y - NSHeight(frame);
    [_window setFrame:frame display:YES];
  }
  if ([position isEqualToString:@"Bottom-Center"]) {
    NSRect frame = [_window frame];
    frame.origin.x = screenRect.origin.x + (NSWidth(screenRect) - NSWidth(frame)) / 2;
    frame.origin.y = screenRect.origin.y - NSHeight(frame);
    [_window setFrame:frame display:YES];
  }
  BOOL shouldForceFullScreenWindow = [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorFullScreen"];
  if ([position isEqualToString:@"Full Screen"] || shouldForceFullScreenWindow) {
    XLOG(@"FULL SCREEN forced=%@", shouldForceFullScreenWindow ? @"true" : @"false");
    NSRect frame = [_window frame];
    frame.size.width = screenRect.size.width;
    frame.size.height = screenRect.size.height - shift;
    frame.origin.x = screenRect.origin.x;
    frame.origin.y = screenRect.origin.y;
    [_window setFrame:frame display:YES];
  }
  if (_background) {
    [[_background contentView] startRendering];
  }
  [self slideWindows:!_isHidden fast:YES];
  NSEnableScreenUpdates();
}

-(void) showVisor:(BOOL)fast {
  AUTO_LOGGERF(@"fast=%d isHidden=%d", fast, _isHidden);
  if (!_isHidden) return;

  [self updateStatusMenu];
  [self storePreviouslyActiveApp];
  [self applyVisorPositioning];

  _isHidden = false;
  [_window makeKeyAndOrderFront:self];
  [_window setHasShadow:YES];
  [NSApp activateIgnoringOtherApps:YES];

  // window will become key eventually, this is important for updatePreviouslyActiveApp to work properly
  // becomeKey event may have delay and without this updatePreviouslyActiveApp could reset PID to 0
  // imagine: when timer fire imediately after showVisor and before becomeKey event
  // see: https://github.com/binaryage/totalterminal/issues/35
  _isKey = true;

  [_window update];
  [self slideWindows:1 fast:fast];
  [_window invalidateShadow];
  [_window update];
}

-(void) hideVisor:(BOOL)fast {
  if (_isHidden) return;

  AUTO_LOGGER();
  _isHidden = true;
  [self updateStatusMenu];
  [_window update];
  [self slideWindows:0 fast:fast];
  [_window setHasShadow:NO];
  [_window invalidateShadow];
  [_window update];
  if (_background) {
    [[_background contentView] stopRendering];
  }

  {
    // in case of Visor and classic Terminal.app window
    // this will prevent a brief window blinking before final focus gets restored
    ScopedNSDisableScreenUpdatesWithDelay disabler(0.1, __FUNCTION__);

    BOOL hadKeyStatus = [_window isKeyWindow];

    // this is important to return focus some other classic Terminal window in case it was active prior Visor sliding down
    // => https://github.com/binaryage/totalterminal/issues/13 and http://getsatisfaction.com/binaryage/topics/return_focus_to_other_terminal_window
    [_window orderOut:self];

    // if visor window loses key status during open-session, do not transfer key status back to previous app
    // see https://github.com/binaryage/totalterminal/issues/26
    if (hadKeyStatus) {
      [self restorePreviouslyActiveApp];       // this is no-op in case Terminal was active app prior Visor sliding down
    }
  }
}

-(void) slideWindows:(BOOL)direction fast:(bool)fast {
  // true == down
  float bkgAlpha = [self getVisorAnimationBackgroundAlpha];

  if (!fast) {
    BOOL doSlide = [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorUseSlide"];
    BOOL doFade = [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorUseFade"];
    float animSpeed = [[NSUserDefaults standardUserDefaults] floatForKey:@"TotalTerminalVisorAnimationSpeed"];

    // HACK for Mountain Lion, fading crashes windowing server on my machine
    if (terminalVersion() >= FIRST_MOUNTAIN_LION_VERSION) {
      if (![[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalDisableMountainLionFadingHack"]) {
        doFade = false;
      }
    }

    // animation loop
    if (doFade || doSlide) {
      if (!doSlide && direction) {
        // setup final slide position in case of no sliding
        float offset = SLIDE_DIRECTION(direction, SLIDE_EASING(1));
        [self placeWindow:_window offset:offset];
      }
      if (!doFade && direction) {
        // setup final alpha state in case of no alpha
        float alpha = ALPHA_DIRECTION(direction, ALPHA_EASING(1));
        if (_background) {
          [_background setAlphaValue:alpha * bkgAlpha];
        }
        [_window setAlphaValue:alpha];
      }
      NSTimeInterval t;
      NSDate* date = [NSDate date];
      while (animSpeed > (t = -[date timeIntervalSinceNow])) {
        // animation update loop
        float k = t / animSpeed;
        if (doSlide) {
          float offset = SLIDE_DIRECTION(direction, SLIDE_EASING(k));
          [self placeWindow:_window offset:offset];
        }
        if (doFade) {
          float alpha = ALPHA_DIRECTION(direction, ALPHA_EASING(k));
          if (_background) {
            [_background setAlphaValue:alpha * bkgAlpha];
          }
          [_window setAlphaValue:alpha];
        }
        usleep(_background ? 1000 : 5000);         // 1 or 5ms
      }
    }
  }

  // apply final slide and alpha states
  float offset = SLIDE_DIRECTION(direction, SLIDE_EASING(1));
  [self placeWindow:_window offset:offset];
  float alpha = ALPHA_DIRECTION(direction, ALPHA_EASING(1));
  [_window setAlphaValue:alpha];
  if (_background) {
    [_background setAlphaValue:alpha * bkgAlpha];
  }
}

-(BOOL) isPinned {
  return [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorPinned"];
}

-(void) resignKey:(id)sender {
  LOG(@"resignKey %@ isMain=%d isKey=%d isHidden=%d isPinned=%d", sender, _isMain, _isKey, _isHidden, [self isPinned]);
  _isKey = false;
  [self updateEscapeHotKeyRegistration];
  [self updateFullScreenHotKeyRegistration];
  if (!_isMain && !_isKey && !_isHidden && ![self isPinned]) {
    [self hideVisor:false];
  }
}

-(void) resignMain:(id)sender {
  LOG(@"resignMain %@ isMain=%d isKey=%d isHidden=%d isPinned=%d", sender, _isMain, _isKey, _isHidden, [self isPinned]);
  _isMain = false;
  if (!_isMain && !_isKey && !_isHidden && ![self isPinned]) {
    [self hideVisor:false];
  }
}

-(void) becomeKey:(id)sender {
  LOG(@"becomeKey %@", sender);
  _isKey = true;
  [self updateEscapeHotKeyRegistration];
  [self updateFullScreenHotKeyRegistration];
}

-(void) becomeMain:(id)sender {
  LOG(@"becomeMain %@", sender);
  _isMain = true;
}

-(void) applicationDidChangeScreenScreenParameters:(NSNotification*)notification {
  AUTO_LOGGERF(@"notification=%@", notification);
  [self resetWindowPlacement];
}

-(void) willClose:(NSNotification*)notification {
  AUTO_LOGGERF(@"notification=%@", notification);
  [self setWindow:nil];
  [self updateStatusMenu];
  [self updateMainMenuState];
}

-(BOOL) isHidden {
  return _isHidden;
}

-(void) registerHotKeyRegistration:(KeyCombo)combo {
  if (!_hotKey) {
    AUTO_LOGGER();
    GTMCarbonEventDispatcherHandler* dispatcher = [NSClassFromString (@"GTMCarbonEventDispatcherHandler")sharedEventDispatcherHandler];
    // setting _hotModifiers means we're not looking for a double tap
    _hotKey = [dispatcher registerHotKey:combo.code
                               modifiers:combo.flags
                                  target:self
                                  action:@selector(toggleVisor:)
                                userInfo:nil
                             whenPressed:YES];
  }
}

-(void) unregisterHotKeyRegistration {
  if (_hotKey) {
    AUTO_LOGGER();
    GTMCarbonEventDispatcherHandler* dispatcher = [NSClassFromString (@"GTMCarbonEventDispatcherHandler")sharedEventDispatcherHandler];
    [dispatcher unregisterHotKey:_hotKey];
    _hotKey = nil;
    _hotModifiers = 0;
  }
}

-(void) updateHotKeyRegistration {
  AUTO_LOGGER();

  [self unregisterHotKeyRegistration];

  DCHECK(_statusMenu);
  if (!_statusMenu) {
    return;     // safety net
  }

  NSMenuItem* statusMenuItem = [_statusMenu itemAtIndex:0];
  NSString* statusMenuItemKey = @"";
  uint statusMenuItemModifiers = 0;
  [statusMenuItem setKeyEquivalent:statusMenuItemKey];
  [statusMenuItem setKeyEquivalentModifierMask:statusMenuItemModifiers];

  NSUserDefaults* ud = [NSUserDefaults standardUserDefaults];

  KeyCombo combo = [self keyComboForShortcut:eToggleVisor];
  BOOL hotkey2Enabled = [ud boolForKey:@"TotalTerminalVisorHotKey2Enabled"];

  if (hotkey2Enabled) {
    // set up double tap if appropriate
    _hotModifiers = [ud integerForKey:@"TotalTerminalVisorHotKey2Mask"];
    if (!_hotModifiers) {
      _hotModifiers = NSAlternateKeyMask;
    }
  }
  if (combo.code != -1) {
    [self registerHotKeyRegistration:combo];

    NSBundle* bundle = [NSBundle bundleForClass:[TotalTerminal class]];
    statusMenuItemKey = [GTMHotKeyTextFieldCell stringForKeycode:combo.code useGlyph:YES resourceBundle:bundle];
    statusMenuItemModifiers = combo.flags;
    [statusMenuItem setKeyEquivalent:statusMenuItemKey];
    [statusMenuItem setKeyEquivalentModifierMask:statusMenuItemModifiers];
  }
}

-(void) registerEscapeHotKeyRegistration {
  if (!_escapeHotKey) {
    AUTO_LOGGER();
    GTMCarbonEventDispatcherHandler* dispatcher = [NSClassFromString (@"GTMCarbonEventDispatcherHandler")sharedEventDispatcherHandler];
    _escapeHotKey = [dispatcher registerHotKey:53     // ESC
                                     modifiers:0
                                        target:self
                                        action:@selector(hideOnEscape:)
                                      userInfo:nil
                                   whenPressed:YES];
  }
}

-(void) unregisterEscapeHotKeyRegistration {
  if (_escapeHotKey) {
    AUTO_LOGGER();
    GTMCarbonEventDispatcherHandler* dispatcher = [NSClassFromString (@"GTMCarbonEventDispatcherHandler")sharedEventDispatcherHandler];
    [dispatcher unregisterHotKey:_escapeHotKey];
    _escapeHotKey = nil;
  }
}

-(void) updateEscapeHotKeyRegistration {
  AUTO_LOGGER();
  BOOL hideOnEscape = [[NSUserDefaults standardUserDefaults] boolForKey:@"TotalTerminalVisorHideOnEscape"];

  if (hideOnEscape && _isKey) {
    [self registerEscapeHotKeyRegistration];
  } else {
    [self unregisterEscapeHotKeyRegistration];
  }
}

-(void) registerFullScreenHotKeyRegistration {
  if (!_fullScreenKey) {
    AUTO_LOGGER();
    // setting _hotModifiers means we're not looking for a double tap
    GTMCarbonEventDispatcherHandler* dispatcher = [NSClassFromString (@"GTMCarbonEventDispatcherHandler")sharedEventDispatcherHandler];
    _fullScreenKey = [dispatcher registerHotKey:0x3     // F
                                      modifiers:NSCommandKeyMask | NSAlternateKeyMask
                                         target:self
                                         action:@selector(fullScreenToggle:)
                                       userInfo:nil
                                    whenPressed:YES];
  }
}

-(void) unregisterFullScreenHotKeyRegistration {
  if (_fullScreenKey) {
    AUTO_LOGGER();
    GTMCarbonEventDispatcherHandler* dispatcher = [NSClassFromString (@"GTMCarbonEventDispatcherHandler")sharedEventDispatcherHandler];
    [dispatcher unregisterHotKey:_fullScreenKey];
    _fullScreenKey = nil;
  }
}

-(void) updateFullScreenHotKeyRegistration {
  AUTO_LOGGER();
  if (_isKey) {
    [self registerFullScreenHotKeyRegistration];
  } else {
    [self unregisterFullScreenHotKeyRegistration];
  }
}

// Returns the amount of time between two clicks to be considered a double click
-(NSTimeInterval) doubleClickTime {
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
  NSTimeInterval doubleClickThreshold = [defaults doubleForKey:@"com.apple.mouse.doubleClickThreshold"];

  // if we couldn't find the value in the user defaults, take a
  // conservative estimate
  if (doubleClickThreshold <= 0.0) {
    doubleClickThreshold = 1.0;
  }
  return doubleClickThreshold;
}

-(void) modifiersChangedWhileActive:(NSEvent*)event {
  // A statemachine that tracks our state via _hotModifiersState. Simple incrementing state.
  if (!_hotModifiers) {
    return;
  }
  NSTimeInterval timeWindowToRespond = _lastHotModifiersEventCheckedTime + [self doubleClickTime];
  _lastHotModifiersEventCheckedTime = [event timestamp];
  if (_hotModifiersState && (_lastHotModifiersEventCheckedTime > timeWindowToRespond)) {
    // Timed out. Reset.
    _hotModifiersState = 0;
    return;
  }
  NSUInteger flags = [event qsbModifierFlags];
  NSLOG3(@"modifiersChangedWhileActive: %@ %08lx %08lx", event, (unsigned long)flags, (unsigned long)_hotModifiers);
  BOOL isGood = NO;
  if (!(_hotModifiersState % 2)) {
    // This is key down cases
    isGood = flags == _hotModifiers;
  } else {
    // This is key up cases
    isGood = flags == 0;
  }
  if (!isGood) {
    // reset
    _hotModifiersState = 0;
    return;
  } else {
    _hotModifiersState += 1;
  }
  NSLOG3(@"  => %ld", (unsigned long)_hotModifiersState);
  if (_hotModifiersState >= 3) {
    // We've worked our way through the state machine to success!
    [self toggleVisor:self];
    _hotModifiersState = 0;
  }
}

// method that is called when a key changes state and we are active
-(void) keysChangedWhileActive:(NSEvent*)event {
  if (!_hotModifiers) return;

  _hotModifiersState = 0;
}

// method that is called when the modifier keys are hit and we are inactive
-(void) modifiersChangedWhileInactive:(NSEvent*)event {
  // If we aren't activated by hotmodifiers, we don't want to be here
  // and if we are in the process of activating, we want to ignore the hotkey
  // so we don't try to process it twice.
  if (!_hotModifiers || [NSApp keyWindow]) return;

  NSUInteger flags = [event qsbModifierFlags];
  NSLOG3(@"modifiersChangedWhileInactive: %@ %08lx %08lx", event, (unsigned long)flags, (unsigned long)_hotModifiers);
  if (flags != _hotModifiers) return;

  const useconds_t oneMilliSecond = 10000;
  UInt16 modifierKeys[] = {
    0,
    kVK_Shift,
    kVK_CapsLock,
    kVK_RightShift,
  };
  if (_hotModifiers == NSControlKeyMask) {
    modifierKeys[0] = kVK_Control;
  } else if (_hotModifiers == NSAlternateKeyMask) {
    modifierKeys[0] = kVK_Option;
  } else if (_hotModifiers == NSCommandKeyMask) {
    modifierKeys[0] = kVK_Command;
  }
  QSBKeyMap* hotMap = [[QSBKeyMap alloc] initWithKeys:modifierKeys count:1];
  QSBKeyMap* invertedHotMap = [[QSBKeyMap alloc] initWithKeys:modifierKeys count:sizeof(modifierKeys) / sizeof(UInt16)];
  invertedHotMap = [invertedHotMap keyMapByInverting];
  NSTimeInterval startDate = [NSDate timeIntervalSinceReferenceDate];
  BOOL isGood = NO;
  while (([NSDate timeIntervalSinceReferenceDate] - startDate) < [self doubleClickTime]) {
    QSBKeyMap* currentKeyMap = [QSBKeyMap currentKeyMap];
    if ([currentKeyMap containsAnyKeyIn:invertedHotMap] || GetCurrentButtonState()) {
      return;
    }
    if (![currentKeyMap containsAnyKeyIn:hotMap]) {
      // Key released;
      isGood = YES;
      break;
    }
    usleep(oneMilliSecond);
  }
  if (!isGood) return;

  isGood = NO;
  startDate = [NSDate timeIntervalSinceReferenceDate];
  while (([NSDate timeIntervalSinceReferenceDate] - startDate) < [self doubleClickTime]) {
    QSBKeyMap* currentKeyMap = [QSBKeyMap currentKeyMap];
    if ([currentKeyMap containsAnyKeyIn:invertedHotMap] || GetCurrentButtonState()) {
      return;
    }
    if ([currentKeyMap containsAnyKeyIn:hotMap]) {
      // Key down
      isGood = YES;
      break;
    }
    usleep(oneMilliSecond);
  }
  if (!isGood) return;

  startDate = [NSDate timeIntervalSinceReferenceDate];
  while (([NSDate timeIntervalSinceReferenceDate] - startDate) < [self doubleClickTime]) {
    QSBKeyMap* currentKeyMap = [QSBKeyMap currentKeyMap];
    if ([currentKeyMap containsAnyKeyIn:invertedHotMap]) {
      return;
    }
    if (![currentKeyMap containsAnyKeyIn:hotMap]) {
      // Key Released
      isGood = YES;
      break;
    }
    usleep(oneMilliSecond);
  }
  if (isGood) {
    [self toggleVisor:self];
  }
}

-(BOOL) status {
  return !!_window;
}

-(BOOL) isVisorWindow:(id)win {
  return _window == win;
}

static const EventTypeSpec kModifierEventTypeSpec[] = { {
                                                          kEventClassKeyboard, kEventRawKeyModifiersChanged
                                                        }
};
static const size_t kModifierEventTypeSpecSize = sizeof(kModifierEventTypeSpec) / sizeof(EventTypeSpec);

// Allows me to intercept the "control" double tap to activate QSB. There
// appears to be no way to do this from straight Cocoa.
-(void) startEventMonitoring {
  GTMCarbonEventMonitorHandler* handler = [GTMCarbonEventMonitorHandler sharedEventMonitorHandler];

  [handler registerForEvents:kModifierEventTypeSpec count:kModifierEventTypeSpecSize];
  [handler setDelegate:self];
}

-(void) stopEventMonitoring {
  GTMCarbonEventMonitorHandler* handler = [GTMCarbonEventMonitorHandler sharedEventMonitorHandler];

  [handler unregisterForEvents:kModifierEventTypeSpec count:kModifierEventTypeSpecSize];
  [handler setDelegate:nil];
}

-(OSStatus) gtm_eventHandler:(GTMCarbonEventHandler*)sender
               receivedEvent:(GTMCarbonEvent*)event
                     handler:(EventHandlerCallRef)handler {
  OSStatus status = eventNotHandledErr;

  if (([event eventClass] == kEventClassKeyboard) &&
      ([event eventKind] == kEventRawKeyModifiersChanged)) {
    UInt32 modifiers;
    if ([event getUInt32ParameterNamed:kEventParamKeyModifiers data:&modifiers]) {
      NSUInteger cocoaMods = GTMCarbonToCocoaKeyModifiers(modifiers);
      NSEvent* nsEvent = [NSEvent    keyEventWithType:NSFlagsChanged
                                             location:[NSEvent mouseLocation]
                                        modifierFlags:cocoaMods
                                            timestamp:[event time]
                                         windowNumber:0
                                              context:nil
                                           characters:nil
                          charactersIgnoringModifiers:nil
                                            isARepeat:NO
                                              keyCode:0];
      [self modifiersChangedWhileInactive:nsEvent];
    }
  }
  return status;
}

-(void) openVisor {
  // prevents showing misplaced visor window briefly
  ScopedNSDisableScreenUpdates disabler(__FUNCTION__);

  id visorProfile = [TotalTerminal getVisorProfile];
  TTApplication* app = (TTApplication*)[NSClassFromString (@"TTApplication")sharedApplication];

  if (terminalVersion() < FIRST_MOUNTAIN_LION_VERSION) {
    [app newWindowControllerWithProfile:visorProfile];
  } else {
    [app makeWindowControllerWithProfile:visorProfile];     // ah, Ben started following Cocoa naming conventions, good! :-)
  }

  [self resetWindowPlacement];
  [self updatePreferencesUI];
  [self updateStatusMenu];
  [self updateMainMenuState];
}

+(void) loadVisor {
  if (terminalVersion() < FIRST_MOUNTAIN_LION_VERSION) {
    SWIZZLE(TTWindowController, newTabWithProfile:);
    if (terminalVersion() < FIRST_LION_VERSION) {
      SWIZZLE(TTWindowController, newTabWithProfile: command: runAsShell:);
    } else {
      SWIZZLE(TTWindowController, newTabWithProfile: customFont: command: runAsShell: restorable: workingDirectory: sessionClass: restoreSession:);
    }
  } else {
    SWIZZLE(TTWindowController, makeTabWithProfile:);
    SWIZZLE(TTWindowController, makeTabWithProfile: customFont: command: runAsShell: restorable: workingDirectory: sessionClass: restoreSession:);
  }
  SWIZZLE(TTWindowController, tabView: didCloseTabViewItem:);

  SWIZZLE(TTTabController, closePane:);
  SWIZZLE(TTTabController, splitPane:);

  SWIZZLE(TTWindowController, setCloseDialogExpected:);
  SWIZZLE(TTWindowController, window: willPositionSheet: usingRect:);

  SWIZZLE(TTWindow, initWithContentRect: styleMask: backing: defer:);
  SWIZZLE(TTWindow, canBecomeKeyWindow);
  SWIZZLE(TTWindow, canBecomeMainWindow);
  SWIZZLE(TTWindow, performClose:);

  SWIZZLE(TTApplication, sendEvent:);

  LOG(@"Visor installed");
}

@end
