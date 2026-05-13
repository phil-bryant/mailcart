#import "OutlookClientBridge.h"
#import <AppKit/AppKit.h>

#include "outlook_client.hpp"
#include "outlook_mailcart.hpp"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace
{
  const int kGraphSearchFetchLimit = 50;
  NSString *const kCursorPrefix = @"__cursor__";

  // #R050: Group request-related NSString values into typed structs to avoid swappable-parameter SAST regressions.
  struct GraphRequestHeaders
  {
    NSString *method;
    NSString *accept;
    NSString *content_type;
  };

  struct MoveMessageRequest
  {
    NSString *message_id;
    NSString *folder_name;
  };

  // #R010: Convert C++ UTF-8 strings into Foundation strings.
  NSString * _Nonnull ToNSString(const std::string &value)
  {
    NSString *result = [[NSString alloc] initWithUTF8String:value.c_str()];
    if (result == nil)
    {
      result = @"";
    }
    return result;
  }

  // #R010: Convert Foundation strings into C++ strings with null-safe fallback.
  std::string ToStdString(NSString *value)
  {
    const char *utf8_value = [value UTF8String];
    std::string result;
    if (utf8_value != nullptr)
    {
      result = utf8_value;
    }
    return result;
  }

  // #R015: Resolve Graph token from runtime environment for live fetches.
  NSString *ResolveGraphToken()
  {
    NSString *token = @"";
    const char *env_value = std::getenv("OUTLOOK_GRAPH_TOKEN");
    if (env_value != nullptr)
    {
      token = [NSString stringWithUTF8String:env_value];
      if (token == nil)
      {
        token = @"";
      }
    }
    NSCharacterSet *whitespace_set = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *token_parts = [token componentsSeparatedByCharactersInSet:whitespace_set];
    NSString *collapsed_token = [token_parts componentsJoinedByString:@""];
    NSString *normalized_token = [collapsed_token stringByTrimmingCharactersInSet:whitespace_set];
    if ([normalized_token hasPrefix:@"Bearer "])
    {
      normalized_token = [normalized_token substringFromIndex:7];
    }
    if ([normalized_token hasPrefix:@"\""] && [normalized_token hasSuffix:@"\""] && normalized_token.length >= 2)
    {
      normalized_token = [normalized_token substringWithRange:NSMakeRange(1, normalized_token.length - 2)];
    }
    token = normalized_token;
    return token;
  }

  NSString *JsonStringOrEmpty(id value)
  {
    NSString *normalized = @"";
    if ([value isKindOfClass:[NSString class]])
    {
      normalized = value;
    }
    return normalized;
  }

  NSDictionary *JsonDictionaryOrEmpty(id value)
  {
    NSDictionary *normalized = @{};
    if ([value isKindOfClass:[NSDictionary class]])
    {
      normalized = value;
    }
    return normalized;
  }

  NSArray *JsonArrayOrEmpty(id value)
  {
    NSArray *normalized = @[];
    if ([value isKindOfClass:[NSArray class]])
    {
      normalized = value;
    }
    return normalized;
  }

  NSString *SerializeJsonObject(id object)
  {
    NSString *serialized = @"{}";
    if ([NSJSONSerialization isValidJSONObject:object])
    {
      NSError *serialization_error = nil;
      NSData *serialized_data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&serialization_error];
      if (serialization_error == nil && serialized_data != nil)
      {
        NSString *candidate = [[NSString alloc] initWithData:serialized_data encoding:NSUTF8StringEncoding];
        if (candidate != nil)
        {
          serialized = candidate;
        }
      }
    }
    return serialized;
  }

  id ParseJsonObject(const std::string &raw_payload)
  {
    id parsed = nil;
    NSString *payload = ToNSString(raw_payload);
    NSData *json_data = [payload dataUsingEncoding:NSUTF8StringEncoding];
    if (json_data != nil)
    {
      NSError *parse_error = nil;
      id parsed_candidate = [NSJSONSerialization JSONObjectWithData:json_data options:0 error:&parse_error];
      if (parse_error == nil && parsed_candidate != nil)
      {
        parsed = parsed_candidate;
      }
    }
    return parsed;
  }

  NSData *FetchGraphGetData(NSURL *url, NSString *token, BOOL binary_accept, NSString **error_text)
  {
    NSData *response_payload = nil;
    NSString *resolved_error = @"";
    if (url == nil)
    {
      resolved_error = @"Graph URL is invalid.";
    }
    else if (token.length == 0)
    {
      resolved_error = @"Missing OUTLOOK_GRAPH_TOKEN.";
    }
    else
    {
      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
      request.HTTPMethod = @"GET";
      NSString *authorization_header = [NSString stringWithFormat:@"Bearer %@", token];
      [request setValue:authorization_header forHTTPHeaderField:@"Authorization"];
      [request setValue:(binary_accept ? @"application/octet-stream" : @"application/json") forHTTPHeaderField:@"Accept"];

      NSHTTPURLResponse *http_response = nil;
      NSError *request_error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      NSData *response_data = [NSURLConnection sendSynchronousRequest:request returningResponse:&http_response error:&request_error];
#pragma clang diagnostic pop
      NSInteger status_code = http_response.statusCode;
      BOOL success = (request_error == nil && response_data != nil && status_code >= 200 && status_code < 300);
      if (success)
      {
        response_payload = response_data;
      }
      else
      {
        if (request_error != nil)
        {
          resolved_error = [NSString stringWithFormat:@"Graph request failed: %@", request_error.localizedDescription];
        }
        else
        {
          resolved_error = [NSString stringWithFormat:@"Graph returned HTTP %ld.", static_cast<long>(status_code)];
        }
      }
    }
    if (error_text != nil)
    {
      *error_text = resolved_error;
    }
    return response_payload;
  }

  NSData *FetchGraphRequestData(
      NSURL *url,
      NSString *token,
      const GraphRequestHeaders &headers,
      NSData *body_data,
      NSString **error_text)
  {
    NSData *response_payload = nil;
    NSString *resolved_error = @"";
    if (url == nil)
    {
      resolved_error = @"Graph URL is invalid.";
    }
    else if (token.length == 0)
    {
      resolved_error = @"Missing OUTLOOK_GRAPH_TOKEN.";
    }
    else
    {
      NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
      request.HTTPMethod = headers.method;
      NSString *authorization_header = [NSString stringWithFormat:@"Bearer %@", token];
      [request setValue:authorization_header forHTTPHeaderField:@"Authorization"];
      if (headers.accept.length > 0)
      {
        [request setValue:headers.accept forHTTPHeaderField:@"Accept"];
      }
      if (headers.content_type.length > 0)
      {
        [request setValue:headers.content_type forHTTPHeaderField:@"Content-Type"];
      }
      if (body_data != nil)
      {
        request.HTTPBody = body_data;
      }

      NSHTTPURLResponse *http_response = nil;
      NSError *request_error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      NSData *response_data = [NSURLConnection sendSynchronousRequest:request returningResponse:&http_response error:&request_error];
#pragma clang diagnostic pop
      NSInteger status_code = http_response.statusCode;
      BOOL success = (request_error == nil && status_code >= 200 && status_code < 300);
      if (success)
      {
        response_payload = response_data == nil ? [NSData data] : response_data;
      }
      else
      {
        if (request_error != nil)
        {
          resolved_error = [NSString stringWithFormat:@"Graph request failed: %@", request_error.localizedDescription];
        }
        else
        {
          resolved_error = [NSString stringWithFormat:@"Graph returned HTTP %ld.", static_cast<long>(status_code)];
        }
      }
    }
    if (error_text != nil)
    {
      *error_text = resolved_error;
    }
    return response_payload;
  }

  NSString *FetchGraphGet(NSString *url_text)
  {
    NSString *response_payload = @"{}";
    NSString *token = ResolveGraphToken();
    NSURL *url = [NSURL URLWithString:url_text];
    NSData *response_data = FetchGraphGetData(url, token, NO, nullptr);
    if (response_data != nil)
    {
      NSString *candidate = [[NSString alloc] initWithData:response_data encoding:NSUTF8StringEncoding];
      if (candidate != nil)
      {
        response_payload = candidate;
      }
    }
    return response_payload;
  }

  NSString *FindMailFolderIdByName(NSString *folder_name)
  {
    NSString *folder_id = @"";
    NSString *token = ResolveGraphToken();
    if (token.length == 0)
    {
      return folder_id;
    }
    NSString *folders_url = @"https://graph.microsoft.com/v1.0/me/mailFolders?$select=id,displayName";
    NSString *raw_folders_payload = FetchGraphGet(folders_url);
    id parsed = ParseJsonObject(ToStdString(raw_folders_payload));
    NSDictionary *root = JsonDictionaryOrEmpty(parsed);
    NSArray *values = JsonArrayOrEmpty(root[@"value"]);
    NSUInteger index = 0;
    while (index < values.count)
    {
      NSDictionary *candidate = JsonDictionaryOrEmpty(values[index]);
      NSString *display_name = JsonStringOrEmpty(candidate[@"displayName"]);
      if ([display_name caseInsensitiveCompare:folder_name] == NSOrderedSame)
      {
        folder_id = JsonStringOrEmpty(candidate[@"id"]);
        break;
      }
      index = index + 1;
    }
    return folder_id;
  }

  NSString *EnsureMailFolderId(NSString *folder_name)
  {
    NSString *existing = FindMailFolderIdByName(folder_name);
    if (existing.length > 0)
    {
      return existing;
    }
    NSString *token = ResolveGraphToken();
    if (token.length == 0)
    {
      return @"";
    }
    NSDictionary *body = @{@"displayName" : folder_name};
    NSData *body_data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSURL *create_url = [NSURL URLWithString:@"https://graph.microsoft.com/v1.0/me/mailFolders"];
    NSString *request_error = @"";
    GraphRequestHeaders create_headers = {
      @"POST",
      @"application/json",
      @"application/json"
    };
    NSData *created_payload = FetchGraphRequestData(
        create_url,
        token,
        create_headers,
        body_data,
        &request_error);
    if (created_payload == nil)
    {
      return @"";
    }
    NSString *json_text = [[NSString alloc] initWithData:created_payload encoding:NSUTF8StringEncoding];
    id parsed = ParseJsonObject(ToStdString(json_text == nil ? @"" : json_text));
    NSDictionary *root = JsonDictionaryOrEmpty(parsed);
    return JsonStringOrEmpty(root[@"id"]);
  }

  BOOL MoveMessageToFolder(const MoveMessageRequest &request)
  {
    BOOL moved = NO;
    NSString *token = ResolveGraphToken();
    if (token.length == 0)
    {
      return moved;
    }
    NSString *destination_folder_id = EnsureMailFolderId(request.folder_name);
    if (destination_folder_id.length == 0)
    {
      return moved;
    }
    NSString *encoded_message_id = [request.message_id stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *move_url_text = [NSString stringWithFormat:@"https://graph.microsoft.com/v1.0/me/messages/%@/move", encoded_message_id];
    NSURL *move_url = [NSURL URLWithString:move_url_text];
    NSDictionary *body = @{@"destinationId" : destination_folder_id};
    NSData *body_data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    GraphRequestHeaders move_headers = {
      @"POST",
      @"application/json",
      @"application/json"
    };
    NSData *response_data = FetchGraphRequestData(
        move_url,
        token,
        move_headers,
        body_data,
        nullptr);
    moved = (response_data != nil);
    return moved;
  }

  NSString *NormalizedAttachmentFileName(NSString *name)
  {
    NSString *normalized_name = @"attachment.bin";
    NSString *candidate = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (candidate.length > 0)
    {
      NSString *without_slashes = [candidate stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
      NSString *without_backslashes = [without_slashes stringByReplacingOccurrencesOfString:@"\\" withString:@"_"];
      normalized_name = without_backslashes;
    }
    return normalized_name;
  }

  NSString *ExtractCursorFromQuery(std::string query)
  {
    NSString *cursor = @"";
    NSString *query_text = ToNSString(query);
    if ([query_text hasPrefix:kCursorPrefix])
    {
      cursor = [query_text substringFromIndex:kCursorPrefix.length];
    }
    return cursor;
  }

  std::string BuildGraphSearchPayload(const std::string &query, int limit)
  {
    std::string payload = "{\"value\":[],\"nextCursor\":\"\",\"error\":\"\"}";
    NSString *token = ResolveGraphToken();
    if (token.length > 0)
    {
      NSString *cursor = ExtractCursorFromQuery(query);
      NSString *messages_url =
          [NSString stringWithFormat:@"https://graph.microsoft.com/v1.0/me/messages?$select=id,subject,bodyPreview,receivedDateTime&$orderby=receivedDateTime%%20DESC&$top=%d",
                                     kGraphSearchFetchLimit];
      if (cursor.length > 0)
      {
        messages_url = cursor;
      }
      NSString *fetch_error = @"";
      NSURL *messages_url_object = [NSURL URLWithString:messages_url];
      NSData *graph_data = FetchGraphGetData(messages_url_object, token, NO, &fetch_error);
      NSArray *values = @[];
      NSString *next_cursor = @"";
      if (graph_data != nil)
      {
        NSString *raw_graph_payload = [[NSString alloc] initWithData:graph_data encoding:NSUTF8StringEncoding];
        id parsed = ParseJsonObject(ToStdString(raw_graph_payload == nil ? @"" : raw_graph_payload));
        NSDictionary *root = JsonDictionaryOrEmpty(parsed);
        values = JsonArrayOrEmpty(root[@"value"]);
        next_cursor = JsonStringOrEmpty(root[@"@odata.nextLink"]);
      }
      NSString *query_text = ToNSString(query);
      if ([query_text hasPrefix:kCursorPrefix])
      {
        query_text = @"";
      }
      NSString *normalized_query = [query_text lowercaseString];
      NSInteger bounded_limit = limit;
      if (bounded_limit < 0)
      {
        bounded_limit = 0;
      }
      NSMutableArray *filtered = [[NSMutableArray alloc] init];
      NSUInteger index = 0;
      while (index < values.count)
      {
        NSDictionary *candidate = JsonDictionaryOrEmpty(values[index]);
        NSString *subject = JsonStringOrEmpty(candidate[@"subject"]);
        NSString *preview = JsonStringOrEmpty(candidate[@"bodyPreview"]);
        NSString *received_at = JsonStringOrEmpty(candidate[@"receivedDateTime"]);
        NSString *subject_lower = [subject lowercaseString];
        NSString *preview_lower = [preview lowercaseString];
        BOOL matches = (normalized_query.length == 0);
        if (!matches && [subject_lower rangeOfString:normalized_query].location != NSNotFound)
        {
          matches = YES;
        }
        if (!matches && [preview_lower rangeOfString:normalized_query].location != NSNotFound)
        {
          matches = YES;
        }
        if (matches && static_cast<NSInteger>(filtered.count) < bounded_limit)
        {
          NSDictionary *summary = @{
            @"id" : JsonStringOrEmpty(candidate[@"id"]),
            @"subject" : subject,
            @"preview" : preview,
            @"receivedAt" : received_at
          };
          [filtered addObject:summary];
        }
        index = index + 1;
      }
      NSDictionary *result_object = @{
        @"value" : filtered,
        @"nextCursor" : next_cursor,
        @"error" : fetch_error
      };
      payload = ToStdString(SerializeJsonObject(result_object));
    }
    else
    {
      NSDictionary *result_object = @{
        @"value" : @[],
        @"nextCursor" : @"",
        @"error" : @"Missing OUTLOOK_GRAPH_TOKEN."
      };
      payload = ToStdString(SerializeJsonObject(result_object));
    }
    return payload;
  }

  NSArray *BuildGraphAttachmentPayload(NSString *message_identifier)
  {
    NSString *token = ResolveGraphToken();
    if (token.length == 0)
    {
      return @[];
    }
    NSString *encoded_identifier = [message_identifier stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *attachments_url =
        [NSString stringWithFormat:@"https://graph.microsoft.com/v1.0/me/messages/%@/attachments?$select=id,name,contentType,size",
                                   encoded_identifier];
    NSString *raw_attachment_payload = FetchGraphGet(attachments_url);
    id parsed = ParseJsonObject(ToStdString(raw_attachment_payload));
    NSDictionary *root = JsonDictionaryOrEmpty(parsed);
    NSArray *values = JsonArrayOrEmpty(root[@"value"]);
    NSMutableArray *normalized = [[NSMutableArray alloc] init];
    NSUInteger index = 0;
    while (index < values.count)
    {
      NSDictionary *candidate = JsonDictionaryOrEmpty(values[index]);
      NSDictionary *attachment = @{
        @"id" : JsonStringOrEmpty(candidate[@"id"]),
        @"name" : JsonStringOrEmpty(candidate[@"name"]),
        @"contentType" : JsonStringOrEmpty(candidate[@"contentType"]),
        @"size" : candidate[@"size"] == nil ? @0 : candidate[@"size"]
      };
      [normalized addObject:attachment];
      index = index + 1;
    }
    return [normalized copy];
  }

  std::string BuildGraphMessagePayload(const std::string &message_id)
  {
    NSDictionary *fallback = @{
      @"id" : ToNSString(message_id),
      @"subject" : @"",
      @"receivedDateTime" : @"",
      @"from" : @{
        @"mailcartAddress" : @{
          @"address" : @""
        }
      },
      @"toRecipients" : @[
        @{
          @"mailcartAddress" : @{
            @"address" : @""
          }
        }
      ],
      @"body" : @{
        @"contentType" : @"text",
        @"content" : @""
      },
      @"attachments" : @[]
    };
    std::string payload = ToStdString(SerializeJsonObject(fallback));
    NSString *token = ResolveGraphToken();
    if (token.length > 0)
    {
      NSString *message_identifier = ToNSString(message_id);
      NSString *encoded_identifier = [message_identifier stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
      NSString *message_url =
          [NSString stringWithFormat:@"https://graph.microsoft.com/v1.0/me/messages/%@?$select=id,subject,body,from,toRecipients,receivedDateTime",
                                     encoded_identifier];
      NSString *fetched_payload = FetchGraphGet(message_url);
      id parsed = ParseJsonObject(ToStdString(fetched_payload));
      if ([parsed isKindOfClass:[NSDictionary class]])
      {
        NSDictionary *dictionary = JsonDictionaryOrEmpty(parsed);
        if (dictionary.count > 0)
        {
          NSMutableDictionary *result_dictionary = [dictionary mutableCopy];
          NSArray *attachments = BuildGraphAttachmentPayload(message_identifier);
          result_dictionary[@"attachments"] = attachments;
          payload = ToStdString(SerializeJsonObject(result_dictionary));
        }
      }
    }
    return payload;
  }
} // namespace

class BridgeOutlookGateway : public OutlookServiceGateway
{
 public:
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

class BridgeOutlookParser : public OutlookPayloadParser
{
 public:
  // #R020: Apply case-insensitive subject/preview search matching.
  // #R025: Enforce non-negative and capped search limits.
  // #R030: Return summary-only payload fields in search responses.
  [[nodiscard]] std::vector<OutlookJsonObject> ParseSearchPayload(const std::string &raw_payload) const override
  {
    std::vector<OutlookJsonObject> parsed_results;
    id parsed = ParseJsonObject(raw_payload);
    NSDictionary *root = JsonDictionaryOrEmpty(parsed);
    NSArray *values = JsonArrayOrEmpty(root[@"value"]);
    NSString *next_cursor = JsonStringOrEmpty(root[@"nextCursor"]);
    NSString *error_text = JsonStringOrEmpty(root[@"error"]);
    NSUInteger index = 0;
    while (index < values.count)
    {
      NSDictionary *candidate = JsonDictionaryOrEmpty(values[index]);
      OutlookJsonObject summary;
      summary.SetStringField("id", ToStdString(JsonStringOrEmpty(candidate[@"id"])));
      summary.SetStringField("subject", ToStdString(JsonStringOrEmpty(candidate[@"subject"])));
      summary.SetStringField("preview", ToStdString(JsonStringOrEmpty(candidate[@"preview"])));
      summary.SetStringField("receivedAt", ToStdString(JsonStringOrEmpty(candidate[@"receivedAt"])));
      parsed_results.push_back(summary);
      index = index + 1;
    }
    if (next_cursor.length > 0)
    {
      OutlookJsonObject cursor_marker;
      cursor_marker.SetStringField("__nextCursor", ToStdString(next_cursor));
      parsed_results.push_back(cursor_marker);
    }
    if (error_text.length > 0)
    {
      OutlookJsonObject error_marker;
      error_marker.SetStringField("__error", ToStdString(error_text));
      parsed_results.push_back(error_marker);
    }
    return parsed_results;
  }

  // #R035: Resolve message reads by id with empty-field fallback for unknown ids.
  [[nodiscard]] OutlookJsonObject ParseMessagePayload(const std::string &raw_payload) const override
  {
    OutlookJsonObject resolved_message;
    id parsed = ParseJsonObject(raw_payload);
    NSDictionary *root = JsonDictionaryOrEmpty(parsed);
    if (root.count > 0)
    {
      NSDictionary *sender_object = JsonDictionaryOrEmpty(root[@"from"]);
      NSDictionary *sender_address = JsonDictionaryOrEmpty(sender_object[@"mailcartAddress"]);
      NSArray *recipients = JsonArrayOrEmpty(root[@"toRecipients"]);
      NSDictionary *first_recipient = @{};
      if (recipients.count > 0)
      {
        first_recipient = JsonDictionaryOrEmpty(recipients[0]);
      }
      NSDictionary *recipient_address = JsonDictionaryOrEmpty(first_recipient[@"mailcartAddress"]);
      NSDictionary *body_object = JsonDictionaryOrEmpty(root[@"body"]);
      NSString *body_type = [[JsonStringOrEmpty(body_object[@"contentType"]) lowercaseString] copy];
      NSString *body_content = JsonStringOrEmpty(body_object[@"content"]);
      NSString *body_text = @"";
      NSString *body_html = @"";
      if ([body_type isEqualToString:@"html"])
      {
        body_html = body_content;
      }
      else
      {
        body_text = body_content;
      }
      resolved_message.SetStringField("id", ToStdString(JsonStringOrEmpty(root[@"id"])));
      resolved_message.SetStringField("sender", ToStdString(JsonStringOrEmpty(sender_address[@"address"])));
      resolved_message.SetStringField("recipient", ToStdString(JsonStringOrEmpty(recipient_address[@"address"])));
      resolved_message.SetStringField("subject", ToStdString(JsonStringOrEmpty(root[@"subject"])));
      resolved_message.SetStringField("receivedAt", ToStdString(JsonStringOrEmpty(root[@"receivedDateTime"])));
      resolved_message.SetStringField("bodyText", ToStdString(body_text));
      resolved_message.SetStringField("bodyHtml", ToStdString(body_html));
      NSArray *attachments = JsonArrayOrEmpty(root[@"attachments"]);
      resolved_message.SetStringField("attachmentCount", std::to_string(static_cast<int>(attachments.count)));
      NSUInteger attachment_index = 0;
      while (attachment_index < attachments.count)
      {
        NSDictionary *attachment_dictionary = JsonDictionaryOrEmpty(attachments[attachment_index]);
        std::string prefix = "attachment" + std::to_string(static_cast<int>(attachment_index));
        resolved_message.SetStringField(prefix + "Id", ToStdString(JsonStringOrEmpty(attachment_dictionary[@"id"])));
        resolved_message.SetStringField(prefix + "Name", ToStdString(JsonStringOrEmpty(attachment_dictionary[@"name"])));
        resolved_message.SetStringField(prefix + "Type", ToStdString(JsonStringOrEmpty(attachment_dictionary[@"contentType"])));
        NSInteger size_value = 0;
        id size_object = attachment_dictionary[@"size"];
        if ([size_object respondsToSelector:@selector(integerValue)])
        {
          size_value = [size_object integerValue];
        }
        resolved_message.SetStringField(prefix + "Size", std::to_string(static_cast<int>(size_value)));
        attachment_index = attachment_index + 1;
      }
    }
    else
    {
      resolved_message.SetStringField("id", "");
      resolved_message.SetStringField("sender", "");
      resolved_message.SetStringField("recipient", "");
      resolved_message.SetStringField("subject", "");
      resolved_message.SetStringField("receivedAt", "");
      resolved_message.SetStringField("bodyText", "");
      resolved_message.SetStringField("bodyHtml", "");
      resolved_message.SetStringField("attachmentCount", "0");
    }
    return resolved_message;
  }
};

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
// #R005: Convert domain summaries into immutable Objective-C summary DTOs.
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
