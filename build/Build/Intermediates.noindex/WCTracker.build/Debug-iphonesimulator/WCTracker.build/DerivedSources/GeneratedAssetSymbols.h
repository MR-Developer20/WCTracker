#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "WC26Badge" asset catalog image resource.
static NSString * const ACImageNameWC26Badge AC_SWIFT_PRIVATE = @"WC26Badge";

#undef AC_SWIFT_PRIVATE
