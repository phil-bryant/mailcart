#include "outlook_client.hpp"
#include <cstddef>
#include <utility>

namespace
{ // #R001: Coerce negative search limits to zero.
  int NormalizeLimit(int requested_limit)
  { int normalized_limit = requested_limit;
    if (normalized_limit < 0)
    { normalized_limit = 0;
    }
    return normalized_limit;
  }
} // namespace

// #R005: Store summary identity and preview fields as immutable state.
OutlookMailcartSummary::OutlookMailcartSummary(std::string message_id, std::string subject, std::string preview, std::string received_at)
    : message_id_(std::move(message_id)),
      subject_(std::move(subject)),
      preview_(std::move(preview)),
      received_at_(std::move(received_at))
{}

const std::string &OutlookMailcartSummary::messageId() const
{ const std::string &value = message_id_;
  return value;
}

const std::string &OutlookMailcartSummary::subject() const
{ const std::string &value = subject_;
  return value;
}

const std::string &OutlookMailcartSummary::preview() const
{ const std::string &value = preview_;
  return value;
}

const std::string &OutlookMailcartSummary::receivedAt() const
{ const std::string &value = received_at_;
  return value;
}

OutlookSearchResult::OutlookSearchResult(
    std::vector<OutlookMailcartSummary> summaries,
    std::string next_cursor,
    std::string error_message)
    : summaries_(std::move(summaries)),
      next_cursor_(std::move(next_cursor)),
      error_message_(std::move(error_message))
{
}

const std::vector<OutlookMailcartSummary> &OutlookSearchResult::summaries() const
{
  const std::vector<OutlookMailcartSummary> &value = summaries_;
  return value;
}

const std::string &OutlookSearchResult::nextCursor() const
{
  const std::string &value = next_cursor_;
  return value;
}

const std::string &OutlookSearchResult::errorMessage() const
{
  const std::string &value = error_message_;
  return value;
}

// #R010: Expose polymorphic cleanup hooks for gateway/parser abstractions.
OutlookServiceGateway::~OutlookServiceGateway() = default;

OutlookPayloadParser::~OutlookPayloadParser() = default;

// #R015: Bind client operations to injected gateway and parser dependencies.
OutlookClient::OutlookClient(const OutlookServiceGateway &gateway, const OutlookPayloadParser &parser)
    : gateway_(gateway), parser_(parser)
{}

// #R020: Fetch and parse search payloads through the gateway-parser pipeline.
// #R025: Map parsed search objects to summaries with default-empty fallback fields.
// #R030: Preserve parser ordering and cardinality in search results.
std::vector<OutlookMailcartSummary> OutlookClient::SearchMailcarts(std::string query, int limit) const
{
  OutlookSearchResult search_result = SearchMailcartsPage(std::move(query), limit, "");
  std::vector<OutlookMailcartSummary> summaries = search_result.summaries();
  return summaries;
}

OutlookSearchResult OutlookClient::SearchMailcartsPage(std::string query, int limit, std::string cursor) const
{
  int normalized_limit = NormalizeLimit(limit);
  std::string raw_query = std::move(query);
  if (!cursor.empty())
  {
    raw_query = "__cursor__" + cursor;
  }
  std::string raw_payload = gateway_.FetchSearchPayload(std::move(raw_query), normalized_limit);
  std::vector<OutlookJsonObject> message_objects = parser_.ParseSearchPayload(raw_payload);
  std::vector<OutlookMailcartSummary> summaries;
  summaries.reserve(message_objects.size());
  std::string next_cursor = "";
  std::string error_message = "";

  std::size_t index = 0;
  while (index < message_objects.size())
  {
    const OutlookJsonObject &message_object = message_objects[index];
    std::string marker = message_object.stringFieldOrDefault("__nextCursor", "");
    std::string error_marker = message_object.stringFieldOrDefault("__error", "");
    if (!marker.empty())
    {
      next_cursor = marker;
    }
    else if (!error_marker.empty())
    {
      error_message = error_marker;
    }
    else
    {
      summaries.emplace_back(
          message_object.stringFieldOrDefault("id", ""),
          message_object.stringFieldOrDefault("subject", ""),
          message_object.stringFieldOrDefault("preview", ""),
          message_object.stringFieldOrDefault("receivedAt", ""));
    }
    index = index + 1;
  }

  OutlookSearchResult search_result(std::move(summaries), std::move(next_cursor), std::move(error_message));
  return search_result;
}

// #R035: Fetch and parse message payload before constructing Outlook mailcart entity.
OutlookMailcart OutlookClient::ReadMailcart(std::string message_id) const
{ std::string raw_payload = gateway_.FetchMessagePayload(std::move(message_id));
  OutlookJsonObject message_object = parser_.ParseMessagePayload(raw_payload);
  OutlookMailcart mailcart(message_object);
  return mailcart;
}
