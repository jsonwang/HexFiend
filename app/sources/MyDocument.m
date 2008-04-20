//
//  MyDocument.m
//  HexFiend_2
//
//  Created by Peter Ammon on 11/3/07.
//  Copyright 2007 __MyCompanyName__. All rights reserved.
//

#import "MyDocument.h"
#import "HFBannerDividerThumb.h"
#import "HFDocumentOperationView.h"
#import <HexFiend/HexFiend.h>
#include <pthread.h>

enum {
	HFSaveSuccessful,
	HFSaveCancelled,
	HFSaveError
};


static BOOL isRunningOnLeopardOrLater(void) {
    return NSAppKitVersionNumber >= 860.;
}

@implementation MyDocument

+ (void)initialize {
	if (self == [MyDocument class]) {
		NSDictionary *defs = [[NSDictionary alloc] initWithObjectsAndKeys:
			[NSNumber numberWithBool:YES], @"AntialiasText",
			@"Monaco", @"DefaultFontName",
			[NSNumber numberWithDouble:10.], @"DefaultFontSize",
			nil];
		[[NSUserDefaults standardUserDefaults] registerDefaults:defs];
		[defs release];
	}
}

- (NSString *)windowNibName {
    // Implement this to return a nib to load OR implement -makeWindowControllers to manually create your controllers.
    return @"MyDocument";
}

- (NSWindow *)window {
    NSArray *windowControllers = [self windowControllers];
    HFASSERT([windowControllers count] == 1);
    return [[windowControllers objectAtIndex:0] window];
}

- (NSArray *)representers {
    return [NSArray arrayWithObjects:lineCountingRepresenter, hexRepresenter, asciiRepresenter, scrollRepresenter, statusBarRepresenter, nil];
}

- (void)showViewForRepresenter:(HFRepresenter *)rep {
    NSView *repView = [rep view];
    HFASSERT([repView superview] == nil && [repView window] == nil);
    [layoutRepresenter addRepresenter:rep];
    [controller addRepresenter:rep];
}

- (void)hideViewForRepresenter:(HFRepresenter *)rep {
    HFASSERT(rep != NULL);
    HFASSERT([[layoutRepresenter representers] indexOfObjectIdenticalTo:rep] != NSNotFound);
    [controller removeRepresenter:rep];
    [layoutRepresenter removeRepresenter:rep];
}

- (void)windowControllerDidLoadNib:(NSWindowController *)windowController {
    USE(windowController);
    
    [containerView setVertical:NO];
    if ([containerView respondsToSelector:@selector(setDividerStyle:)]) {
		[containerView setDividerStyle:2/*NSSplitViewDividerStyleThin*/];
    }
    [containerView setDelegate:self];
    
    NSView *layoutView = [layoutRepresenter view];
    [layoutView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [layoutView setFrame:[containerView bounds]];
    [containerView addSubview:layoutView];
    
    [self showViewForRepresenter:hexRepresenter];
    [self showViewForRepresenter:asciiRepresenter];
    [self showViewForRepresenter:scrollRepresenter];
    [self showViewForRepresenter:lineCountingRepresenter];
    [self showViewForRepresenter:statusBarRepresenter];
}

/* When our line counting view needs more space, we increase the size of our window, and also move it left by the same amount so that the other content does not appear to move. */
- (void)lineCountingViewChangedWidth:(NSNotification *)note {
    HFASSERT([note object] == lineCountingRepresenter);
    NSView *lineCountingView = [lineCountingRepresenter view];
    
    /* Don't do anything window changing if we're not in a window yet */
    NSWindow *lineCountingViewWindow = [lineCountingView window];
    if (! lineCountingViewWindow) return;
    
    HFASSERT(lineCountingViewWindow == [self window]);
    
    CGFloat currentWidth = NSWidth([lineCountingView frame]);
    CGFloat newWidth = [lineCountingRepresenter preferredWidth];
    if (newWidth != currentWidth) {
        CGFloat widthChange = newWidth - currentWidth; //if we shrink, widthChange will be negative
        CGFloat windowWidthChange = [[lineCountingView superview] convertSize:NSMakeSize(widthChange, 0) toView:nil].width;
        windowWidthChange = (windowWidthChange < 0 ? HFFloor(windowWidthChange) : HFCeil(windowWidthChange));
        
        /* convertSize: has a nasty habit of stomping on negatives.  Make our window width change negative if our view-space horizontal change was negative. */
#if __LP64__
        windowWidthChange = copysign(windowWidthChange, widthChange);
#else
        windowWidthChange = copysignf(windowWidthChange, widthChange);
#endif
        
        NSRect windowFrame = [lineCountingViewWindow frame];
        windowFrame.size.width += windowWidthChange;
        windowFrame.origin.x -= windowWidthChange;
        [lineCountingViewWindow setFrame:windowFrame display:YES animate:NO];
    }
}

- init {
    [super init];
    lineCountingRepresenter = [[HFLineCountingRepresenter alloc] init];
    hexRepresenter = [[HFHexTextRepresenter alloc] init];
    asciiRepresenter = [[HFStringEncodingTextRepresenter alloc] init];
    scrollRepresenter = [[HFVerticalScrollerRepresenter alloc] init];
    layoutRepresenter = [[HFLayoutRepresenter alloc] init];
    statusBarRepresenter = [[HFStatusBarRepresenter alloc] init];
    
    [[hexRepresenter view] setAutoresizingMask:NSViewHeightSizable];
    [[asciiRepresenter view] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(lineCountingViewChangedWidth:) name:HFLineCountingRepresenterMinimumViewWidthChanged object:lineCountingRepresenter];
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	
    controller = [[HFController alloc] init];
	[controller setShouldAntialias:[defs boolForKey:@"AntialiasText"]];
    [controller setUndoManager:[self undoManager]];
    [controller addRepresenter:layoutRepresenter];
    
    
#if ! NDEBUG
    static BOOL hasAddedMenu = NO;
    if (! hasAddedMenu) {
        hasAddedMenu = YES;
        NSMenu *menu = [[[NSApp mainMenu] itemWithTitle:@"Debug"] submenu];
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItemWithTitle:@"Show ByteArray" action:@selector(_showByteArray:) keyEquivalent:@"k"];
        [[[menu itemArray] lastObject] setKeyEquivalentModifierMask:NSCommandKeyMask];
    }
#endif
    return self;
}

#if ! NDEBUG
- (void)_showByteArray:sender {
    USE(sender);
    NSLog(@"%@", [controller byteArray]);
}
#endif

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[self representers] makeObjectsPerformSelector:@selector(release)];
    [controller release];
    [bannerView release];
    [super dealloc];
}

- (HFDocumentOperationView *)createOperationViewOfName:(NSString *)name {
	HFASSERT(name);
	HFDocumentOperationView *result = [[HFDocumentOperationView viewWithNibNamed:name] retain];
	[result setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[result setFrameSize:NSMakeSize(NSWidth([containerView frame]), 0)];
	[result setFrameOrigin:NSZeroPoint];	
	return result;
}

- (void)prepareBannerWithView:(HFDocumentOperationView *)newSubview withTargetFirstResponder:(id)targetFirstResponder {
	HFASSERT(operationView == nil);
	operationView = newSubview;
	bannerTargetHeight = [newSubview defaultHeight];
    if (! bannerView) bannerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
    NSRect containerBounds = [containerView bounds];
    NSRect bannerFrame = NSMakeRect(NSMinX(containerBounds), NSMaxY(containerBounds), NSWidth(containerBounds), 0);
    [bannerView setFrame:bannerFrame];
    bannerStartTime = 0;
    bannerIsShown = YES;
    bannerGrowing = YES;
	targetFirstResponderInBanner = targetFirstResponder;
    if (isRunningOnLeopardOrLater()) {
        if (! bannerDividerThumb) bannerDividerThumb = [[HFBannerDividerThumb alloc] initWithFrame:NSMakeRect(0, 0, 14, 14)];
        [bannerDividerThumb setAutoresizingMask:0];
        [bannerDividerThumb setFrameOrigin:NSMakePoint(3, 0)];
        [bannerDividerThumb removeFromSuperview];
        [bannerView addSubview:bannerDividerThumb];
    }
    if (newSubview) {
        if (bannerDividerThumb) [bannerView addSubview:newSubview positioned:NSWindowBelow relativeTo:bannerDividerThumb];
        else [bannerView addSubview:newSubview];
    }
    [NSTimer scheduledTimerWithTimeInterval:1. / 60. target:self selector:@selector(animateBanner:) userInfo:nil repeats:YES];
}


- (BOOL)readFromURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError {
    USE(typeName);
    USE(outError);
    BOOL result = NO;
    HFASSERT([absoluteURL isFileURL]);
    HFFileReference *fileReference = [[[HFFileReference alloc] initWithPath:[absoluteURL path]] autorelease];
    if (fileReference) {
        HFFileByteSlice *byteSlice = [[[HFFileByteSlice alloc] initWithFile:fileReference] autorelease];
        HFTavlTreeByteArray *byteArray = [[[HFTavlTreeByteArray alloc] init] autorelease];
        [byteArray insertByteSlice:byteSlice inRange:HFRangeMake(0, 0)];
        [controller setByteArray:byteArray];
        result = YES;
    }
    return result;
}

- (IBAction)toggleVisibleControllerView:(id)sender {
    USE(sender);
    NSUInteger arrayIndex = [sender tag] - 1;
    NSArray *representers = [self representers];
    if (arrayIndex >= [representers count]) {
        NSBeep();
    }
    else {
        HFRepresenter *rep = [representers objectAtIndex:arrayIndex];
        NSView *repView = [rep view];
        if ([repView window] == [self window]) {
            [self hideViewForRepresenter:rep];
        }
        else {
            [self showViewForRepresenter:rep];
        }
    }
}

- (void)setFont:(NSFont *)font {
	HFASSERT(font != nil);
	NSWindow *window = [self window];
	NSDisableScreenUpdates();
	[controller setFont:font];
	[window display];
	NSEnableScreenUpdates();
	NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
	[defs setDouble:[font pointSize] forKey:@"DefaultFontSize"];
	[defs setObject:[font fontName] forKey:@"DefaultFontName"];
	
}

- (NSFont *)font {
	return [controller font];
}

- (void)setFontSizeFromMenuItem:(NSMenuItem *)item {
	NSString *fontName = [[self font] fontName];
	[self setFont:[NSFont fontWithName:fontName size:(CGFloat)[item tag]]];
}

- (IBAction)setAntialiasFromMenuItem:(id)sender {
	USE(sender);
	BOOL newVal = ! [controller shouldAntialias];
	[controller setShouldAntialias:newVal];
	[[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"AntialiasText"];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(toggleVisibleControllerView:)) {
        NSUInteger arrayIndex = [item tag] - 1;
        NSArray *representers = [self representers];
        if (arrayIndex >= [representers count]) {
            return NO;
        }
        else {
            HFRepresenter *rep = [representers objectAtIndex:arrayIndex];
            [item setState:[[controller representers] containsObject:rep]];
            return YES;
        }
    }
    else if ([item action] == @selector(performFindPanelAction:)) {
        switch ([item tag]) {
            case NSFindPanelActionShowFindPanel:
            case NSFindPanelActionNext:
            case NSFindPanelActionPrevious:
                return YES;
            default:
                return NO;
        }
    }
	else if ([item action] == @selector(setFontSizeFromMenuItem:)) {
		[item setState:[[self font] pointSize] == [item tag]];
		return YES;
	}
	else if ([item action] == @selector(setAntialiasFromMenuItem:)) {
		[item setState:[controller shouldAntialias]];
		return YES;		
	}
    else return [super validateMenuItem:item];
}

- (void)finishedAnimation {
    if (! bannerGrowing) {
		bannerIsShown = NO;
		[bannerDividerThumb removeFromSuperview];
		[bannerView removeFromSuperview];
		[[[[bannerView subviews] copy] autorelease] makeObjectsPerformSelector:@selector(removeFromSuperview)];
		[bannerView release];
		bannerView = nil;
		operationView = nil;
        [containerView setNeedsDisplay:YES];
		if (commandToRunAfterBannerIsDoneHiding) {
			SEL command = commandToRunAfterBannerIsDoneHiding;
			commandToRunAfterBannerIsDoneHiding = NULL;
			[self performSelector:command withObject:nil];
		}
    }
}

- (void)restoreFirstResponderToSavedResponder {
    NSWindow *window = [self window];
    NSMutableArray *views = [NSMutableArray array];
    FOREACH(HFRepresenter *, rep, [self representers]) {
        NSView *view = [rep view];
        if ([view window] == window) {
            /* If we're the saved first responder, try it first */
            if (view == savedFirstResponder) [views insertObject:view atIndex:0];
            else [views addObject:view];
        }
    }
    
    /* Try each view we identified */
    FOREACH(NSView *, view, views) {
        if ([window makeFirstResponder:view]) return;
    }
    
    /* No luck - set it to the window */
    [window makeFirstResponder:window];
}

- (void)animateBanner:(NSTimer *)timer {
    BOOL isFirstCall = (bannerStartTime == 0);
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (isFirstCall) bannerStartTime = now;
    CFAbsoluteTime diff = now - bannerStartTime;
    double amount = diff / .15;
    amount = fmin(fmax(amount, 0), 1);
    if (! bannerGrowing) amount = 1. - amount;
	if (bannerGrowing && diff >= 0 && [bannerView superview] != containerView) {
		[containerView addSubview:bannerView positioned:NSWindowBelow relativeTo:[layoutRepresenter view]];
		if (targetFirstResponderInBanner) {
			NSWindow *window = [self window];
			savedFirstResponder = [window firstResponder];
			[window makeFirstResponder:targetFirstResponderInBanner];
		}
	}
    CGFloat height = (CGFloat)round(bannerTargetHeight * amount);
    NSRect bannerFrame = [bannerView frame];
    bannerFrame.size.height = height;
    [bannerView setFrame:bannerFrame];
    [containerView display];
    if (isFirstCall) {
        /* The first display can take some time, which can cause jerky animation; so we start the animation after it */
        bannerStartTime = CFAbsoluteTimeGetCurrent();
    }
    if ((bannerGrowing && amount >= 1.) || (!bannerGrowing && amount <= 0.)) {
		[timer invalidate];
		[self finishedAnimation];
    }
}

- (BOOL)canSwitchToNewBanner {
	return operationView == nil || operationView != saveView;
}

- (void)hideBannerFirstThenDo:(SEL)command {
    HFASSERT(bannerIsShown);
    bannerGrowing = NO;
    bannerStartTime = 0;
    /* If the first responder is in our banner, move it to our view */
    NSWindow *window = [self window];
    id firstResponder = [window firstResponder];
	bannerTargetHeight = NSHeight([bannerView frame]);
	commandToRunAfterBannerIsDoneHiding = command;
    if ([firstResponder isKindOfClass:[NSView class]] && [firstResponder ancestorSharedWithView:bannerView] == bannerView) {
        [self restoreFirstResponderToSavedResponder];
    }
    [NSTimer scheduledTimerWithTimeInterval:1. / 60. target:self selector:@selector(animateBanner:) userInfo:nil repeats:YES];
}

- (void)hideBannerImmediately {
    HFASSERT(bannerIsShown);
	NSWindow *window = [self window];
    bannerGrowing = NO;
    bannerStartTime = 0;
	bannerTargetHeight = NSHeight([bannerView frame]);
    /* If the first responder is in our banner, move it to our view */
    id firstResponder = [window firstResponder];
    if ([firstResponder isKindOfClass:[NSView class]] && [firstResponder ancestorSharedWithView:bannerView] == bannerView) {
        [self restoreFirstResponderToSavedResponder];
    }
	while (bannerIsShown) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		[self animateBanner:nil];
		[window displayIfNeeded];
		[pool release];
	}
}

- (void)showSaveBannerHavingDelayed:(NSTimer *)timer {
	HFASSERT(saveView != nil);
	USE(timer);
	if (operationView != nil && operationView != saveView) {
		[self hideBannerImmediately];
	}
    [self prepareBannerWithView:saveView withTargetFirstResponder:nil];
}

- (BOOL)writeSafelyToURL:(NSURL *)inAbsoluteURL ofType:(NSString *)inTypeName forSaveOperation:(NSSaveOperationType)saveOperation error:(NSError **)outError {
    USE(inTypeName);
    *outError = NULL;
	
	NSTimer *showSaveBannerTimer = [NSTimer scheduledTimerWithTimeInterval:.5 target:self selector:@selector(showSaveBannerHavingDelayed:) userInfo:nil repeats:NO];
    
	if (! saveView) saveView = [self createOperationViewOfName:@"SaveBanner"];
	saveResult = 0;

    struct HFDocumentOperationCallbacks callbacks = {
        .target = self,
        .userInfo = [NSDictionary dictionaryWithObjectsAndKeys:inAbsoluteURL, @"targetURL", nil],
        .startSelector = @selector(threadedStartSave:),
        .endSelector = @selector(endSave:)
    };
	
    [[controller byteArray] incrementChangeLockCounter];
	
    [saveView startOperationWithCallbacks:callbacks];
    
    while ([saveView operationIsRunning]) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        @try {  
            NSEvent *event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:[NSDate distantFuture] inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event) [NSApp sendEvent:event];
        }
        @catch (NSException *localException) {
            NSLog(@"Exception thrown during save: %@", localException);
        }
        @finally {
            [pool drain];
        }
    }
	
	[showSaveBannerTimer invalidate];
	
    [[controller byteArray] decrementChangeLockCounter];
	
	if (saveOperation == NSSaveOperation || saveOperation == NSSaveAsOperation) {
		/* We can no longer undo, since we may have overwritten our source data. */
		[[self undoManager] removeAllActions];	
		HFFileReference *fileReference = [[[HFFileReference alloc] initWithPath:[inAbsoluteURL path]] autorelease];
		if (fileReference) {
			HFFileByteSlice *byteSlice = [[[HFFileByteSlice alloc] initWithFile:fileReference] autorelease];
			HFTavlTreeByteArray *byteArray = [[[HFTavlTreeByteArray alloc] init] autorelease];
			[byteArray insertByteSlice:byteSlice inRange:HFRangeMake(0, 0)];
			[controller setByteArray:byteArray];
		}
	}
	
    
	if (operationView != nil && operationView == saveView) [self hideBannerFirstThenDo:NULL];
	
    return saveResult != HFSaveError;
}

- (void)showFindPanel:(NSMenuItem *)item {
	if (operationView != nil && operationView == findReplaceView) return;
	if (! [self canSwitchToNewBanner]) {
		NSBeep();
		return;
	}
    USE(item);
    if (bannerIsShown) {
		[self hideBannerFirstThenDo:_cmd];
		return;
    }
	
    if (! findReplaceView) {
        findReplaceView = [self createOperationViewOfName:@"FindReplaceBanner"];
        [[findReplaceView viewNamed:@"searchField"] setTarget:self];
        [[findReplaceView viewNamed:@"searchField"] setAction:@selector(findNext:)];
        [[findReplaceView viewNamed:@"replaceField"] setTarget:self];
        [[findReplaceView viewNamed:@"replaceField"] setAction:@selector(findNext:)];
    }
    
    [self prepareBannerWithView:findReplaceView withTargetFirstResponder:[findReplaceView viewNamed:@"searchField"]];
}

- (NSRect)splitView:(NSSplitView *)splitView additionalEffectiveRectOfDividerAtIndex:(NSInteger)dividerIndex {
    USE(dividerIndex);
    HFASSERT(splitView == containerView);
    if (bannerDividerThumb) return [bannerDividerThumb convertRect:[bannerDividerThumb bounds] toView:containerView];
    else return NSZeroRect;
}

- (void)cancelOperation:sender {
    USE(sender);
    [self hideBannerFirstThenDo:NULL];
}

- (id)threadedStartSave:(HFProgressTracker *)tracker {
    HFByteArray *byteArray = [controller byteArray];
    NSDictionary *userInfo = [tracker userInfo];
    NSURL *targetURL = [userInfo objectForKey:@"targetURL"];
    NSError *error = nil;
    BOOL result = [byteArray writeToFile:targetURL trackingProgress:tracker error:&error];
	[tracker noteFinished:self];
	if (tracker->cancelRequested) return [NSNumber numberWithInt:HFSaveCancelled];
	else if (! result) return [NSNumber numberWithInt:HFSaveError];
	else return [NSNumber numberWithInt:HFSaveSuccessful];
}

- (void)endSave:(id)result {
    NSLog(@"End save %@", result);
	saveResult = [result integerValue];
	/* Post an event so our event loop wakes up */
	[NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:NULL subtype:0 data1:0 data2:0] atStart:NO];
}

- (id)threadedStartFind:(HFProgressTracker *)tracker {
    HFASSERT(tracker != NULL);
    unsigned long long searchResult;
    NSDictionary *userInfo = [tracker userInfo];
    HFByteArray *needle = [userInfo objectForKey:@"needle"];
    HFByteArray *haystack = [userInfo objectForKey:@"haystack"];
    BOOL forwards = [[userInfo objectForKey:@"forwards"] boolValue];
    HFRange searchRange1 = [[userInfo objectForKey:@"range1"] HFRange];
    HFRange searchRange2 = [[userInfo objectForKey:@"range2"] HFRange];
    
    [tracker setMaxProgress:[haystack length]];
    
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    searchResult = [haystack indexOfBytesEqualToBytes:needle inRange:searchRange1 searchingForwards:forwards trackingProgress:tracker];
    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    printf("Diff: %f\n", end - start);
	
    if (searchResult == ULLONG_MAX) {
        searchResult = [haystack indexOfBytesEqualToBytes:needle inRange:searchRange2 searchingForwards:forwards trackingProgress:tracker];
    }
    
    if (tracker->cancelRequested) return nil;
    else return [[NSNumber alloc] initWithUnsignedLongLong:searchResult]; //released by spinUntilFinished
}

- (void)findEnded:(NSNumber *)val {
    NSLog(@"%llu", [val unsignedLongLongValue]);
    NSDictionary *userInfo = [[findReplaceView progressTracker] userInfo];
    HFByteArray *needle = [userInfo objectForKey:@"needle"];
    HFByteArray *haystack = [userInfo objectForKey:@"haystack"];
    /* nil val means cancelled */
    if (val) {
        unsigned long long searchResult = [val unsignedLongLongValue];
        if (searchResult != ULLONG_MAX) {
			
            HFRange resultRange = HFRangeMake(searchResult, [needle length]);
            [controller setSelectedContentsRanges:[HFRangeWrapper withRanges:&resultRange count:1]];
            [controller maximizeVisibilityOfContentsRange:resultRange];
            [self restoreFirstResponderToSavedResponder];
        }
        else {
            NSBeep();
        }
    }
    [needle decrementChangeLockCounter];
    [haystack decrementChangeLockCounter];
	
}

- (void)findNextBySearchingForwards:(BOOL)forwards {
    HFByteArray *needle = [[findReplaceView viewNamed:@"searchField"] objectValue];
    if ([needle length] > 0) {
        HFByteArray *haystack = [controller byteArray];
        unsigned long long startLocation = [controller maximumSelectionLocation];
        unsigned long long endLocation = [controller minimumSelectionLocation];
        unsigned long long haystackLength = [haystack length];
        HFASSERT(startLocation <= [haystack length]);
        HFRange searchRange1 = HFRangeMake(startLocation, haystackLength - startLocation);
        HFRange searchRange2 = HFRangeMake(0, endLocation);
        
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
								  needle, @"needle",
								  haystack, @"haystack",
								  [NSNumber numberWithBool:forwards], @"forwards",
								  [HFRangeWrapper withRange:searchRange1], @"range1",
								  [HFRangeWrapper withRange:searchRange2], @"range2",
								  nil];
        
        struct HFDocumentOperationCallbacks callbacks = {
            .target = self,
            .userInfo = userInfo,
            .startSelector = @selector(threadedStartFind:),
            .endSelector = @selector(findEnded:)
        };
        
        [needle incrementChangeLockCounter];
        [haystack incrementChangeLockCounter];
        
        [findReplaceView startOperationWithCallbacks:callbacks];
    }
}

- (void)findNext:sender {
    USE(sender);
    [self findNextBySearchingForwards:YES];
}

- (void)findPrevious:sender {
    USE(sender);
    [self findNextBySearchingForwards:NO];
}

- (void)performFindPanelAction:(NSMenuItem *)item {
    switch ([item tag]) {
        case NSFindPanelActionShowFindPanel:
            [self showFindPanel:item];
            break;
        case NSFindPanelActionNext:
            [self findNext:item];
            break;
        case NSFindPanelActionPrevious:
            [self findPrevious:item];
            break;
        default:
            NSLog(@"Unhandled item %@", item);
            break;
    }
}

- (void)showNavigationBanner {
	if (navigateView == operationView && navigateView != nil) return;
    if (! navigateView) navigateView = [self createOperationViewOfName:@"DataNavigate"];
    [self prepareBannerWithView:navigateView withTargetFirstResponder:nil];
	
}

- (void)moveSelectionForwards:(NSMenuItem *)sender {
	USE(sender);
	if (! [self canSwitchToNewBanner]) {
		NSBeep();
		return;
	}
    if (operationView != nil && operationView != navigateView) {
		[self hideBannerFirstThenDo:_cmd];
		return;
    }
	[self showNavigationBanner];
}

- (void)moveSelectionBackwards:(NSMenuItem *)sender {
	USE(sender);
	if (! [self canSwitchToNewBanner]) {
		NSBeep();
		return;
	}
    if (operationView != nil && operationView != navigateView) {
		[self hideBannerFirstThenDo:_cmd];
		return;
    }
	[self showNavigationBanner];
}

- (void)extendSelectionForwards:(NSMenuItem *)sender {
	USE(sender);
	if (! [self canSwitchToNewBanner]) {
		NSBeep();
		return;
	}
    if (operationView != nil && operationView != navigateView) {
		[self hideBannerFirstThenDo:_cmd];
		return;
    }
	[self showNavigationBanner];
}

- (void)extendSelectionBackwards:(NSMenuItem *)sender {
	USE(sender);
	if (! [self canSwitchToNewBanner]) {
		NSBeep();
		return;
	}
    if (operationView != nil && operationView != navigateView) {
		[self hideBannerFirstThenDo:_cmd];
		return;
    }
	[self showNavigationBanner];
}

- (IBAction)showFontPanel:(id)sender {
	NSFontPanel *panel = [NSFontPanel sharedFontPanel];
	[panel orderFront:sender];
	[panel setPanelFont:[self font] isMultiple:NO];
}

- (void)changeFont:(id)sender {
	[self setFont:[sender convertFont:[self font]]];
}

@end
