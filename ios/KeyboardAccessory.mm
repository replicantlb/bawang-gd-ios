#import <UIKit/UIKit.h>
#import <objc/runtime.h>

namespace {
using CommonInit = void (*)(id, SEL);
CommonInit originalCommonInit;

void dismissKeyboard(id object, SEL, id) {
	UITextView *input = (UITextView *)object;
	if (!input.isFirstResponder) {
		return;
	}
	// Finish an active IME composition before Godot clears its native buffer in
	// resignFirstResponder. Do not send Return: TextEdit may be multiline.
	[input unmarkText];
	[input resignFirstResponder];
}

void initializeKeyboard(id object, SEL selector) {
	originalCommonInit(object, selector);
	UITextView *input = (UITextView *)object;
	if (input.inputAccessoryView != nil) {
		return;
	}
	UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 0, 44)];
	toolbar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	UIBarButtonItem *dismiss = [[UIBarButtonItem alloc] initWithTitle:@"收起键盘" style:UIBarButtonItemStyleProminent target:input action:sel_registerName("bawangDismissKeyboard:")];
	dismiss.accessibilityIdentifier = @"bawang.keyboard.dismiss";
	toolbar.items = @[space, dismiss];
	input.inputAccessoryView = toolbar;
}
}

@interface BawangKeyboardAccessory : NSObject
@end

@implementation BawangKeyboardAccessory
+ (void)load {
	Class input = objc_getClass("GodotKeyboardInputView");
	Method initialize = class_getInstanceMethod(input, sel_registerName("godot_commonInit"));
	NSMethodSignature *signature = initialize ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(initialize)] : nil;
	if (input == Nil || ![input isSubclassOfClass:[UITextView class]] || signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(void)) != 0) {
		NSLog(@"BawangIOS: Godot keyboard initialization method unavailable.");
		return;
	}
	if (!class_addMethod(input, sel_registerName("bawangDismissKeyboard:"), reinterpret_cast<IMP>(dismissKeyboard), "v@:@")) {
		NSLog(@"BawangIOS: Godot keyboard dismissal method already exists.");
		return;
	}
	originalCommonInit = reinterpret_cast<CommonInit>(method_getImplementation(initialize));
	method_setImplementation(initialize, reinterpret_cast<IMP>(initializeKeyboard));
}
@end
