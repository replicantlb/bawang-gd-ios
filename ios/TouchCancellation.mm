#import <Foundation/Foundation.h>
#import <objc/runtime.h>

namespace {
using CancelTouches = void (*)(id, SEL, NSSet *, id);
using ClearTouches = void (*)(id, SEL);
using RemoveTouch = int (*)(id, SEL, id);

CancelTouches originalCancel;
ClearTouches originalClear;
RemoveTouch originalRemove;
SEL removeTouchSelector;
thread_local void *viewInCancellation = nullptr;

void clearTouches(id view, SEL selector) {
	if ((__bridge void *)view != viewInCancellation) {
		originalClear(view, selector);
	}
}

void cancelTouches(id view, SEL selector, NSSet *touches, id event) {
	void *previousView = viewInCancellation;
	viewInCancellation = (__bridge void *)view;
	// Keep the engine's cancelled event, but free only the slots UIKit cancelled.
	for (id touch in touches) {
		originalCancel(view, selector, [NSSet setWithObject:touch], event);
		originalRemove(view, removeTouchSelector, touch);
	}
	viewInCancellation = previousView;
}
}

@interface BawangTouchCancellation : NSObject
@end

@implementation BawangTouchCancellation
+ (void)load {
	Class view = objc_getClass("GodotView");
	Method cancel = class_getInstanceMethod(view, sel_registerName("touchesCancelled:withEvent:"));
	Method clear = class_getInstanceMethod(view, sel_registerName("clearTouches"));
	removeTouchSelector = sel_registerName("removeTouch:");
	Method remove = class_getInstanceMethod(view, removeTouchSelector);
	if (!cancel || !clear || !remove) {
		NSLog(@"BawangIOS: Godot touch cancellation methods unavailable.");
		return;
	}

	originalCancel = reinterpret_cast<CancelTouches>(method_getImplementation(cancel));
	originalClear = reinterpret_cast<ClearTouches>(method_getImplementation(clear));
	originalRemove = reinterpret_cast<RemoveTouch>(method_getImplementation(remove));
	method_setImplementation(clear, reinterpret_cast<IMP>(clearTouches));
	method_setImplementation(cancel, reinterpret_cast<IMP>(cancelTouches));
}
@end
