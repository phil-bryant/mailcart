#import <Foundation/Foundation.h>
#import "OutlookBridgeModels.h"

NS_ASSUME_NONNULL_BEGIN

// #R001: Expose Objective-C bridge operations for search and read.
// #R040: Own and expose bridge lifecycle around C++ client dependencies.
@interface OutlookClientBridge : NSObject

// #R001: Expose Objective-C bridge search entrypoint backed by the C++ client.
// #R045: Return Objective-C DTO summaries for Swift UI consumption.
- (OutlookSearchResultDTO *)searchMailcartsWithQuery:(NSString *)query
                                            limit:(NSInteger)limit
                                           cursor:(NSString *)cursor;

// #R001: Expose Objective-C bridge read entrypoint backed by the C++ client.
// #R045: Return an immutable Objective-C full-mailcart DTO for Swift UI consumption.
- (OutlookMailcartDTO *)readMailcartWithMessageId:(NSString *)messageId;

- (BOOL)openAttachmentWithMessageId:(NSString *)messageId
                        attachmentId:(NSString *)attachmentId
                          fileName:(NSString *)fileName;

- (BOOL)moveMessageToFolderWithMessageId:(NSString *)messageId
                              folderName:(NSString *)folderName;

@end

NS_ASSUME_NONNULL_END
