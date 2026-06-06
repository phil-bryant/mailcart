#import <Foundation/Foundation.h>
#include <string>

namespace mailcart_bridge
{
  // #R010: Convert C++ UTF-8 strings into Foundation strings.
  NSString *ToNSString(const std::string &value);

  // #R010: Convert Foundation strings into C++ strings with null-safe fallback.
  std::string ToStdString(NSString *value);

  // JSON normalization helpers shared across Graph payload building and parsing.
  NSString *JsonStringOrEmpty(id value);
  NSDictionary *JsonDictionaryOrEmpty(id value);
  NSArray *JsonArrayOrEmpty(id value);
  NSString *SerializeJsonObject(id object);
  id ParseJsonObject(const std::string &raw_payload);
} // namespace mailcart_bridge
