#import <Foundation/Foundation.h>

namespace mailcart_bridge
{
  // #R050: Group request-related NSString values into typed structs to avoid swappable-parameter SAST regressions.
  struct GraphRequestHeaders
  {
    NSString *method;
    NSString *accept;
    NSString *content_type;
  };

  // #R050: Group move-message identifiers into a typed struct to avoid swappable NSString parameters.
  struct MoveMessageRequest
  {
    NSString *message_id;
    NSString *folder_name;
  };

  // #R050: Move a Graph message into a destination folder using the typed move request struct.
  BOOL MoveMessageToFolder(const MoveMessageRequest &request);
} // namespace mailcart_bridge
