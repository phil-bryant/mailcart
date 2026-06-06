#import "outlook_client.hpp"
#import "outlook_mailcart.hpp"

#include <string>
#include <vector>

// Bridge-side OutlookPayloadParser that maps Graph JSON payloads into domain JSON objects.
class BridgeOutlookParser : public OutlookPayloadParser
{ public:
  [[nodiscard]] std::vector<OutlookJsonObject> ParseSearchPayload(const std::string &raw_payload) const override;

  // #R035: Resolve message reads by id with empty-field fallback for unknown ids.
  [[nodiscard]] OutlookJsonObject ParseMessagePayload(const std::string &raw_payload) const override;
};
