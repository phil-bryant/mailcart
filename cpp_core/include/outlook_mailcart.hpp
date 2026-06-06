#pragma once
#include "mailcart.hpp"
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

// #R001: Declare the Outlook mailcart interface (JSON object wrapper, attachment value type, and the OutlookMailcart entity with metadata accessors and type() override).
class OutlookJsonObject
{ public:
  OutlookJsonObject();
  void SetStringField(std::string key, std::string value);
  [[nodiscard]] bool hasField(const std::string &key) const;
  [[nodiscard]] std::string stringFieldOrDefault(const std::string &key, std::string_view default_value) const;

  private:
  std::unordered_map<std::string, std::string> string_fields_;
};

class OutlookAttachment
{ public:
  OutlookAttachment(std::string attachment_id, std::string file_name, std::string content_type, int size_in_bytes);
  [[nodiscard]] const std::string &attachmentId() const;
  [[nodiscard]] const std::string &fileName() const;
  [[nodiscard]] const std::string &contentType() const;
  [[nodiscard]] int sizeInBytes() const;

  private:
  std::string attachment_id_;
  std::string file_name_;
  std::string content_type_;
  int size_in_bytes_;
};

class OutlookMailcart : public Mailcart
{ public:
  explicit OutlookMailcart(const OutlookJsonObject &json_object) noexcept(false);
  OutlookMailcart(const OutlookMailcart &other) noexcept(false) = default; // #R001: Defaulted copy constructor is part of the value-type interface.
  OutlookMailcart &operator=(const OutlookMailcart &other) noexcept(false) = default; // #R001: Defaulted copy assignment preserves value-type semantics.
  [[nodiscard]] const std::string &messageId() const;
  [[nodiscard]] const std::string &receivedAt() const;
  [[nodiscard]] const std::string &bodyText() const;
  [[nodiscard]] const std::string &bodyHtml() const;
  [[nodiscard]] const std::vector<OutlookAttachment> &attachments() const;
  [[nodiscard]] std::string type() const override;

  private:
  std::string message_id_;
  std::string received_at_;
  std::string body_text_;
  std::string body_html_;
  std::vector<OutlookAttachment> attachments_;
};
