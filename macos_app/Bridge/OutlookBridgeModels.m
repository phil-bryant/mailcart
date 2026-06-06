#import "OutlookBridgeModels.h"

@implementation OutlookMailcartSummaryDTO

// #R005: Materialize immutable summary DTO values through the designated initializer.
- (instancetype)initWithMessageId:(NSString *)messageId
                          subject:(NSString *)subject
                          preview:(NSString *)preview
                       receivedAt:(NSString *)receivedAt
{
  self = [super init];
  if (self != nil)
  {
    _messageId = [messageId copy];
    _subject = [subject copy];
    _preview = [preview copy];
    _receivedAt = [receivedAt copy];
  }
  return self;
}

@end

@implementation OutlookSearchResultDTO

- (instancetype)initWithSummaries:(NSArray<OutlookMailcartSummaryDTO *> *)summaries
                       nextCursor:(NSString *)nextCursor
                     errorMessage:(NSString *)errorMessage
{
  self = [super init];
  if (self != nil)
  {
    _summaries = [summaries copy];
    _nextCursor = [nextCursor copy];
    _errorMessage = [errorMessage copy];
  }
  return self;
}

@end

@implementation OutlookAttachmentDTO

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                            fileName:(NSString *)fileName
                         contentType:(NSString *)contentType
                         sizeInBytes:(NSInteger)sizeInBytes
{
  self = [super init];
  if (self != nil)
  {
    _attachmentId = [attachmentId copy];
    _fileName = [fileName copy];
    _contentType = [contentType copy];
    _sizeInBytes = sizeInBytes;
  }
  return self;
}

@end

@implementation OutlookMailcartDTO

// #R005: Materialize immutable full-mailcart DTO values through the designated initializer.
- (instancetype)initWithMessageId:(NSString *)messageId
                           sender:(NSString *)sender
                        recipient:(NSString *)recipient
                          subject:(NSString *)subject
                       receivedAt:(NSString *)receivedAt
                             body:(NSString *)body
                         bodyText:(NSString *)bodyText
                         bodyHtml:(NSString *)bodyHtml
                      attachments:(NSArray<OutlookAttachmentDTO *> *)attachments
{
  self = [super init];
  if (self != nil)
  {
    _messageId = [messageId copy];
    _sender = [sender copy];
    _recipient = [recipient copy];
    _subject = [subject copy];
    _receivedAt = [receivedAt copy];
    _body = [body copy];
    _bodyText = [bodyText copy];
    _bodyHtml = [bodyHtml copy];
    _attachments = [attachments copy];
  }
  return self;
}

@end
