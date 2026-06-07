#import "OutlookClientBridge.h"
#import "OutlookBridgeParser.h"
#import "OutlookGraphConversions.h"
#import "OutlookGraphHttpClient.h"
#import "OutlookGraphMessageMover.h"
#import <AppKit/AppKit.h>

#include "outlook_client.hpp"
#include "outlook_mailcart.hpp"

#include <memory>
#include <string>
#include <utility>
#include <vector>

using namespace mailcart_bridge;

class BridgeOutlookGateway : public OutlookServiceGateway
{ public:
  // #R001: Expose search payload fetch operation for bridge client flow.
  [[nodiscard]] std::string FetchSearchPayload(std::string query, int limit) const override
  {
    std::string payload = BuildGraphSearchPayload(query, limit);
    return payload;
  }

  // #R001: Expose message payload fetch operation for bridge client flow.
  [[nodiscard]] std::string FetchMessagePayload(std::string message_id) const override
  {
    std::string payload = BuildGraphMessagePayload(message_id);
    return payload;
  }
};

// #R040: Own the bridge gateway/parser and managed C++ client lifecycle state.
@interface OutlookClientBridge ()
{
 @private
  BridgeOutlookGateway _gateway;
  BridgeOutlookParser _parser;
  std::unique_ptr<OutlookClient> _client;
}
@end

@implementation OutlookClientBridge

// #R040: Instantiate and own C++ Outlook client dependencies in bridge lifecycle.
- (instancetype)init
{
  self = [super init];
  if (self != nil)
  {
    _client = std::make_unique<OutlookClient>(_gateway, _parser);
  }
  return self;
}

// #R001: Expose Objective-C bridge search operation.
// #R045: Map C++ search results into Objective-C DTO arrays.
- (OutlookSearchResultDTO *)searchMailcartsWithQuery:(NSString *)query
                                            limit:(NSInteger)limit
                                           cursor:(NSString *)cursor
{
  std::string query_value = ToStdString(query);
  std::string cursor_value = ToStdString(cursor);
  OutlookSearchResult search_result = _client->SearchMailcartsPage(
      std::move(query_value),
      static_cast<int>(limit),
      std::move(cursor_value));
  std::vector<OutlookMailcartSummary> summaries = search_result.summaries();

  NSMutableArray<OutlookMailcartSummaryDTO *> *result = [[NSMutableArray alloc] initWithCapacity:summaries.size()];
  std::size_t index = 0;
  while (index < summaries.size())
  {
    const OutlookMailcartSummary &summary = summaries[index];
    OutlookMailcartSummaryDTO *dto = [[OutlookMailcartSummaryDTO alloc] initWithMessageId:ToNSString(summary.messageId())
                                                                              subject:ToNSString(summary.subject())
                                                                              preview:ToNSString(summary.preview())
                                                                           receivedAt:ToNSString(summary.receivedAt())];
    [result addObject:dto];
    index = index + 1;
  }
  NSArray<OutlookMailcartSummaryDTO *> *immutable_result = [result copy];
  OutlookSearchResultDTO *dto_result = [[OutlookSearchResultDTO alloc] initWithSummaries:immutable_result
                                                                               nextCursor:ToNSString(search_result.nextCursor())
                                                                             errorMessage:ToNSString(search_result.errorMessage())];
  return dto_result;
}

// #R001: Expose Objective-C bridge read operation.
// #R045: Map C++ read result into Objective-C full mailcart DTO.
- (OutlookMailcartDTO *)readMailcartWithMessageId:(NSString *)messageId
{
  std::string message_id = ToStdString(messageId);
  OutlookMailcart mailcart = _client->ReadMailcart(std::move(message_id));
  NSMutableArray<OutlookAttachmentDTO *> *attachment_dtos = [[NSMutableArray alloc] initWithCapacity:mailcart.attachments().size()];
  std::size_t attachment_index = 0;
  while (attachment_index < mailcart.attachments().size())
  {
    const OutlookAttachment &attachment = mailcart.attachments()[attachment_index];
    OutlookAttachmentDTO *attachment_dto = [[OutlookAttachmentDTO alloc] initWithAttachmentId:ToNSString(attachment.attachmentId())
                                                                                       fileName:ToNSString(attachment.fileName())
                                                                                    contentType:ToNSString(attachment.contentType())
                                                                                    sizeInBytes:attachment.sizeInBytes()];
    [attachment_dtos addObject:attachment_dto];
    attachment_index = attachment_index + 1;
  }
  OutlookMailcartDTO *dto = [[OutlookMailcartDTO alloc] initWithMessageId:ToNSString(mailcart.messageId())
                                                              sender:ToNSString(mailcart.sender())
                                                           recipient:ToNSString(mailcart.recipient())
                                                             subject:ToNSString(mailcart.subject())
                                                          receivedAt:ToNSString(mailcart.receivedAt())
                                                                body:ToNSString(mailcart.body())
                                                            bodyText:ToNSString(mailcart.bodyText())
                                                            bodyHtml:ToNSString(mailcart.bodyHtml())
                                                         attachments:[attachment_dtos copy]];
  return dto;
}

// #R050: Download a Graph attachment payload and open the staged temp file.
- (BOOL)openAttachmentWithMessageId:(NSString *)messageId
                       attachmentId:(NSString *)attachmentId
                           fileName:(NSString *)fileName
{
  BOOL opened = NO;
  NSString *token = ResolveGraphToken();
  if (token.length > 0)
  {
    NSString *encoded_message_id = [messageId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *encoded_attachment_id = [attachmentId stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *attachment_url =
        [NSString stringWithFormat:@"https://graph.microsoft.com/v1.0/me/messages/%@/attachments/%@/$value",
                                   encoded_message_id,
                                   encoded_attachment_id];
    NSURL *attachment_url_object = [NSURL URLWithString:attachment_url];
    NSData *attachment_data = FetchGraphGetData(attachment_url_object, token, YES, nullptr);
    if (attachment_data != nil)
    {
      NSString *resolved_file_name = NormalizedAttachmentFileName(fileName);
      NSString *temporary_directory = NSTemporaryDirectory();
      NSString *temporary_file_path = [temporary_directory stringByAppendingPathComponent:resolved_file_name];
      NSError *write_error = nil;
      BOOL wrote_file = [attachment_data writeToFile:temporary_file_path options:NSDataWritingAtomic error:&write_error];
      if (wrote_file && write_error == nil)
      {
        NSURL *temporary_file_url = [NSURL fileURLWithPath:temporary_file_path];
        opened = [[NSWorkspace sharedWorkspace] openURL:temporary_file_url];
      }
    }
  }
  return opened;
}

// #R055: Normalize target folder input and dispatch a move request.
- (BOOL)moveMessageToFolderWithMessageId:(NSString *)messageId
                              folderName:(NSString *)folderName
{
  NSString *resolved_folder_name = [folderName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (resolved_folder_name.length == 0)
  {
    resolved_folder_name = @"matchy";
  }
  MoveMessageRequest request = {
    messageId,
    resolved_folder_name
  };
  return MoveMessageToFolder(request);
}

@end
