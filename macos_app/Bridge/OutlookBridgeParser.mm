#import "OutlookBridgeParser.h"
#import "OutlookGraphConversions.h"
#import <Foundation/Foundation.h>

#include <string>
#include <vector>

using namespace mailcart_bridge;

// #R035: Parse Graph search payload objects into summary/cursor/error markers.
std::vector<OutlookJsonObject> BridgeOutlookParser::ParseSearchPayload(const std::string &raw_payload) const
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
OutlookJsonObject BridgeOutlookParser::ParseMessagePayload(const std::string &raw_payload) const
{
  OutlookJsonObject resolved_message;
  id parsed = ParseJsonObject(raw_payload);
  NSDictionary *root = JsonDictionaryOrEmpty(parsed);
  if (root.count > 0)
  {
    NSDictionary *sender_object = JsonDictionaryOrEmpty(root[@"from"]);
    NSDictionary *sender_address = JsonDictionaryOrEmpty(sender_object[@"emailAddress"]);
    NSArray *recipients = JsonArrayOrEmpty(root[@"toRecipients"]);
    NSDictionary *first_recipient = @{};
    if (recipients.count > 0)
    {
      first_recipient = JsonDictionaryOrEmpty(recipients[0]);
    }
    NSDictionary *recipient_address = JsonDictionaryOrEmpty(first_recipient[@"emailAddress"]);
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
