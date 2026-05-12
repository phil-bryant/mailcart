#pragma once
#include "outlook_mailcart.hpp"
#include <string>
#include <vector>

class OutlookMailcartSummary
{ public:
  OutlookMailcartSummary(std::string message_id, std::string subject, std::string preview, std::string received_at);
  [[nodiscard]] const std::string &messageId() const;
  [[nodiscard]] const std::string &subject() const;
  [[nodiscard]] const std::string &preview() const;
  [[nodiscard]] const std::string &receivedAt() const;

  private:
  std::string message_id_;
  std::string subject_;
  std::string preview_;
  std::string received_at_;
};

class OutlookSearchResult
{ public:
  OutlookSearchResult(std::vector<OutlookMailcartSummary> summaries, std::string next_cursor, std::string error_message);
  [[nodiscard]] const std::vector<OutlookMailcartSummary> &summaries() const;
  [[nodiscard]] const std::string &nextCursor() const;
  [[nodiscard]] const std::string &errorMessage() const;

  private:
  std::vector<OutlookMailcartSummary> summaries_;
  std::string next_cursor_;
  std::string error_message_;
};

class OutlookServiceGateway
{ public:
  virtual ~OutlookServiceGateway();
  [[nodiscard]] virtual std::string FetchSearchPayload(std::string query, int limit) const = 0;
  [[nodiscard]] virtual std::string FetchMessagePayload(std::string message_id) const = 0;
};

class OutlookPayloadParser
{ public:
  virtual ~OutlookPayloadParser();
  [[nodiscard]] virtual std::vector<OutlookJsonObject> ParseSearchPayload(const std::string &raw_payload) const = 0;
  [[nodiscard]] virtual OutlookJsonObject ParseMessagePayload(const std::string &raw_payload) const = 0;
};

class OutlookClient
{ public:
  OutlookClient(const OutlookServiceGateway &gateway, const OutlookPayloadParser &parser);
  [[nodiscard]] std::vector<OutlookMailcartSummary> SearchMailcarts(std::string query, int limit) const;
  [[nodiscard]] OutlookSearchResult SearchMailcartsPage(std::string query, int limit, std::string cursor) const;
  [[nodiscard]] OutlookMailcart ReadMailcart(std::string message_id) const;

  private:
  const OutlookServiceGateway &gateway_;
  const OutlookPayloadParser &parser_;
};
