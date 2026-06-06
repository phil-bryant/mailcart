#import "OutlookGraphConversions.h"
#import <Foundation/Foundation.h>

#include <string>

namespace mailcart_bridge
{
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
} // namespace mailcart_bridge
