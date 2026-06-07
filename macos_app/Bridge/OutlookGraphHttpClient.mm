#import "OutlookGraphHttpClient.h"
#import "OutlookGraphConversions.h"
#import <Foundation/Foundation.h>

#include <cstdlib>
#include <string>

namespace mailcart_bridge
{
  namespace
  {
    const int kGraphSearchFetchLimit = 50;
    NSString *const kCursorPrefix = @"__cursor__";
    GraphSynchronousTransport g_graph_transport_hook = nullptr;
    GraphRefreshHook g_graph_refresh_hook = nullptr;
    GraphTokenResolverHook g_graph_token_resolver_hook = nullptr;

    // #R015: Resolve Graph token from shared cache or runtime environment for live fetches.
    NSString *NormalizeGraphToken(NSString *token)
    {
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
      return normalized_token == nil ? @"" : normalized_token;
    }

    // #R015: Resolve the OAuth cache file path under the user's home directory.
    NSString *GraphTokenCachePath()
    {
      const char *home_value = std::getenv("HOME");
      if (home_value == nullptr)
      {
        return @"";
      }
      return [NSString stringWithFormat:@"%s/.cache/mailcart/graph_oauth.json", home_value];
    }

    // #R015: Load and validate an access token from the OAuth cache file.
    NSString *TokenFromCacheFile()
    {
      NSString *cache_path = GraphTokenCachePath();
      if (cache_path.length == 0)
      {
        return @"";
      }
      NSData *cache_data = [NSData dataWithContentsOfFile:cache_path];
      if (cache_data == nil)
      {
        return @"";
      }
      NSError *parse_error = nil;
      id parsed_candidate = [NSJSONSerialization JSONObjectWithData:cache_data options:0 error:&parse_error];
      if (parse_error != nil || ![parsed_candidate isKindOfClass:[NSDictionary class]])
      {
        return @"";
      }
      NSDictionary *cache = (NSDictionary *)parsed_candidate;
      NSString *raw_access_token = @"";
      id access_value = cache[@"access_token"];
      if ([access_value isKindOfClass:[NSString class]])
      {
        raw_access_token = access_value;
      }
      NSString *access_token = NormalizeGraphToken(raw_access_token);
      if (access_token.length == 0)
      {
        return @"";
      }
      id expires_value = cache[@"expires_at"];
      if ([expires_value respondsToSelector:@selector(doubleValue)])
      {
        NSTimeInterval expires_at = [expires_value doubleValue];
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (expires_at > 0 && expires_at <= now + 300)
        {
          return @"";
        }
      }
      return access_token;
    }
  } // namespace

  // #R055: Install deterministic replay hooks for Graph transport/auth flows in integration tests.
  void InstallGraphTransportHook(GraphSynchronousTransport hook)
  {
    g_graph_transport_hook = hook;
  }

  // #R055: Install deterministic replay hooks for Graph transport/auth flows in integration tests.
  void InstallGraphRefreshHook(GraphRefreshHook hook)
  {
    g_graph_refresh_hook = hook;
  }

  // #R055: Install deterministic replay hooks for Graph transport/auth flows in integration tests.
  void InstallGraphTokenResolverHook(GraphTokenResolverHook hook)
  {
    g_graph_token_resolver_hook = hook;
  }

  // #R055: Install deterministic replay hooks for Graph transport/auth flows in integration tests.
  void ResetGraphTestHooks()
  {
    g_graph_transport_hook = nullptr;
    g_graph_refresh_hook = nullptr;
    g_graph_token_resolver_hook = nullptr;
  }

  // #R015: Refresh cached Graph credentials when a live request reports HTTP 401.
  BOOL AttemptRefreshGraphToken()
  {
    if (g_graph_refresh_hook != nullptr)
    {
      return g_graph_refresh_hook();
    }
    const char *repo_root = std::getenv("MAILCART_REPO_ROOT");
    if (repo_root == nullptr)
    {
      return NO;
    }
    NSString *script_path = [NSString stringWithFormat:@"%s/scripts/refresh_graph_token.py", repo_root];
    if (![[NSFileManager defaultManager] fileExistsAtPath:script_path])
    {
      return NO;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/python3";
    task.arguments = @[script_path, @"--force"];
    task.environment = [NSProcessInfo processInfo].environment;
    @try
    {
      [task launch];
      [task waitUntilExit];
      return task.terminationStatus == 0;
    }
    @catch (NSException *)
    {
      return NO;
    }
  }

  // #R015: Resolve Graph token from shared cache or runtime environment for live fetches.
  NSString *ResolveGraphToken()
  {
    if (g_graph_token_resolver_hook != nullptr)
    {
      NSString *resolved = g_graph_token_resolver_hook();
      return NormalizeGraphToken(resolved == nil ? @"" : resolved);
    }
    NSString *token = TokenFromCacheFile();
    if (token.length == 0)
    {
      const char *env_value = std::getenv("OUTLOOK_GRAPH_TOKEN");
      if (env_value != nullptr)
      {
        token = [NSString stringWithUTF8String:env_value];
        if (token == nil)
        {
          token = @"";
        }
      }
    }
    return NormalizeGraphToken(token);
  }

  NSString *TruncatedResponseBodyText(NSData *response_data)
  {
    NSString *body_text = @"";
    if (response_data != nil && response_data.length > 0)
    {
      NSString *decoded = [[NSString alloc] initWithData:response_data encoding:NSUTF8StringEncoding];
      if (decoded != nil)
      {
        body_text = [decoded stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      }
    }
    if (body_text.length > 300)
    {
      body_text = [body_text substringToIndex:300];
    }
    return body_text;
  }

  NSData *PerformRequestSynchronously(NSURLRequest *request, NSHTTPURLResponse **http_response, NSError **request_error)
  {
    if (g_graph_transport_hook != nullptr)
    {
      return g_graph_transport_hook(request, http_response, request_error);
    }
    NSData *captured_data = nil;
    NSHTTPURLResponse *captured_http_response = nil;
    NSError *captured_error = nil;
    NSURLResponse *captured_response = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    captured_data = [NSURLConnection sendSynchronousRequest:request returningResponse:&captured_response error:&captured_error];
#pragma clang diagnostic pop
    if ([captured_response isKindOfClass:[NSHTTPURLResponse class]])
    {
      captured_http_response = (NSHTTPURLResponse *)captured_response;
    }
    if (http_response != nil)
    {
      *http_response = captured_http_response;
    }
    if (request_error != nil)
    {
      *request_error = captured_error;
    }
    return captured_data;
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
      NSString *attempt_token = token;
      for (int attempt = 0; attempt < 2; ++attempt)
      {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"GET";
        NSString *authorization_header = [NSString stringWithFormat:@"Bearer %@", attempt_token];
        [request setValue:authorization_header forHTTPHeaderField:@"Authorization"];
        [request setValue:(binary_accept ? @"application/octet-stream" : @"application/json") forHTTPHeaderField:@"Accept"];

        NSHTTPURLResponse *http_response = nil;
        NSError *request_error = nil;
        NSData *response_data = PerformRequestSynchronously(request, &http_response, &request_error);
        NSInteger status_code = http_response.statusCode;
        BOOL success = (request_error == nil && response_data != nil && status_code >= 200 && status_code < 300);
        if (success)
        {
          response_payload = response_data;
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

  // #R015: Perform authenticated Graph JSON GET requests with token resolution.
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

  // #R040: Normalize attachment names to a safe basename with fallback.
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

  namespace
  {
    // #R035: Extract a pagination cursor from "__cursor__" query markers.
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

    // #R020: Accept pagination cursors only for trusted Graph HTTPS message endpoints.
    BOOL IsTrustedGraphNextCursor(NSString *cursor)
    {
      if (cursor.length == 0)
      {
        return YES;
      }
      NSURLComponents *components = [NSURLComponents componentsWithString:cursor];
      if (components == nil)
      {
        return NO;
      }
      NSString *scheme = [components.scheme lowercaseString];
      NSString *host = [components.host lowercaseString];
      NSString *path = components.path == nil ? @"" : components.path;
      return [scheme isEqualToString:@"https"] &&
             [host isEqualToString:@"graph.microsoft.com"] &&
             [path hasPrefix:@"/v1.0/me/messages"];
    }
  } // namespace

  // #R020: Apply case-insensitive subject/preview search matching.
  // #R025: Enforce non-negative and capped search limits.
  // #R030: Return summary-only payload fields in search responses.
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
        if (!IsTrustedGraphNextCursor(next_cursor))
        {
          next_cursor = @"";
          fetch_error = @"Graph pagination returned an unexpected host.";
        }
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

  namespace
  {
    // #R045: Build normalized Graph attachment payload rows for a message id.
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
  } // namespace

  // #R050: Build a deterministic single-message payload with merged attachments.
  std::string BuildGraphMessagePayload(const std::string &message_id)
  {
    NSDictionary *fallback = @{
      @"id" : ToNSString(message_id),
      @"subject" : @"",
      @"receivedDateTime" : @"",
      @"from" : @{
        @"emailAddress" : @{
          @"address" : @""
        }
      },
      @"toRecipients" : @[
        @{
          @"emailAddress" : @{
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
} // namespace mailcart_bridge
