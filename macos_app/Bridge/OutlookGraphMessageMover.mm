#import "OutlookGraphMessageMover.h"
#import "OutlookGraphConversions.h"
#import "OutlookGraphHttpClient.h"
#import <Foundation/Foundation.h>

#include <string>

namespace mailcart_bridge
{
  namespace
  {
    // #R050: Send an authenticated Graph request described by a typed header struct, retrying once on HTTP 401.
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
        NSString *attempt_token = token;
        for (int attempt = 0; attempt < 2; ++attempt)
        {
          NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
          request.HTTPMethod = headers.method;
          NSString *authorization_header = [NSString stringWithFormat:@"Bearer %@", attempt_token];
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
          NSData *response_data = PerformRequestSynchronously(request, &http_response, &request_error);
          NSInteger status_code = http_response.statusCode;
          BOOL success = (request_error == nil && status_code >= 200 && status_code < 300);
          if (success)
          {
            response_payload = response_data == nil ? [NSData data] : response_data;
            resolved_error = @"";
            break;
          }

          if (request_error != nil)
          {
            resolved_error = [NSString stringWithFormat:@"Graph request failed: %@ (%@, code %ld).",
                                                        request_error.localizedDescription,
                                                        request_error.domain,
                                                        static_cast<long>(request_error.code)];
          }
          else
          {
            NSString *response_body = TruncatedResponseBodyText(response_data);
            if (response_body.length > 0)
            {
              resolved_error = [NSString stringWithFormat:@"Graph returned HTTP %ld: %@",
                                                              static_cast<long>(status_code),
                                                              response_body];
            }
            else
            {
              resolved_error = [NSString stringWithFormat:@"Graph returned HTTP %ld.", static_cast<long>(status_code)];
            }
          }

          if (status_code == 401 && attempt == 0 && AttemptRefreshGraphToken())
          {
            attempt_token = ResolveGraphToken();
            if (attempt_token.length > 0)
            {
              continue;
            }
          }
          break;
        }
      }
      if (error_text != nil)
      {
        *error_text = resolved_error;
      }
      return response_payload;
    }

    // #R055: Resolve destination folder ids by case-insensitive display-name lookup.
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

    // #R060: Ensure destination folder ids exist, creating folders when missing.
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
  } // namespace

  // #R050: Move a Graph message into a destination folder using the typed move request struct.
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
} // namespace mailcart_bridge
