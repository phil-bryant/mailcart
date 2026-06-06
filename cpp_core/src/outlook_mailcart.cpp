#include "outlook_mailcart.hpp"
#include <cstdlib>
#include <utility>

namespace
{ // #R001: Prefer text body over HTML when both are present.
  // #R005: Fallback to unknown empty MIME content when body fields are absent.
  MimeContent BuildMimeContentFromJson(const OutlookJsonObject &json_object)
  {
    std::string text_body = json_object.stringFieldOrDefault("bodyText", "");
    std::string html_body = json_object.stringFieldOrDefault("bodyHtml", "");
    MimeContent mime_content("application/unknown", "");
    if (!text_body.empty())
    {
      mime_content = MimeContent::PlainText(std::move(text_body));
    }
    else if (!html_body.empty())
    {
      mime_content = MimeContent::Html(std::move(html_body));
    }
    return mime_content;
  }

  // #R040: Parse a non-negative attachment count from attachmentCount text.
  int ParseAttachmentCount(const OutlookJsonObject &json_object)
  {
    int attachment_count = 0;
    std::string attachment_count_text = json_object.stringFieldOrDefault("attachmentCount", "0");
    char *parse_end = nullptr;
    long parsed_value = std::strtol(attachment_count_text.c_str(), &parse_end, 10);
    if (parse_end != nullptr && *parse_end == '\0' && parsed_value > 0)
    {
      attachment_count = static_cast<int>(parsed_value);
    }
    return attachment_count;
  }

  // #R045: Build indexed attachment records from attachmentN* JSON fields.
  std::vector<OutlookAttachment> BuildAttachmentsFromJson(const OutlookJsonObject &json_object)
  {
    std::vector<OutlookAttachment> attachments;
    int attachment_count = ParseAttachmentCount(json_object);
    int attachment_index = 0;
    while (attachment_index < attachment_count)
    {
      std::string attachment_prefix = "attachment" + std::to_string(attachment_index);
      std::string attachment_id = json_object.stringFieldOrDefault(attachment_prefix + "Id", "");
      std::string file_name = json_object.stringFieldOrDefault(attachment_prefix + "Name", "");
      std::string content_type = json_object.stringFieldOrDefault(attachment_prefix + "Type", "");
      std::string size_text = json_object.stringFieldOrDefault(attachment_prefix + "Size", "0");
      char *size_parse_end = nullptr;
      long parsed_size = std::strtol(size_text.c_str(), &size_parse_end, 10);
      int size_in_bytes = 0;
      if (size_parse_end != nullptr && *size_parse_end == '\0' && parsed_size > 0)
      {
        size_in_bytes = static_cast<int>(parsed_size);
      }
      attachments.emplace_back(
          std::move(attachment_id),
          std::move(file_name),
          std::move(content_type),
          size_in_bytes);
      attachment_index = attachment_index + 1;
    }
    return attachments;
  }
} // namespace

OutlookJsonObject::OutlookJsonObject() = default;

// #R010: Support mutable string-field insertion into JSON wrappers.
void OutlookJsonObject::SetStringField(std::string key, std::string value)
{
  string_fields_[std::move(key)] = std::move(value);
}

// #R015: Report field presence by exact key membership.
bool OutlookJsonObject::hasField(const std::string &key) const
{
  bool has_key = false;
  if (string_fields_.find(key) != string_fields_.end())
  {
    has_key = true;
  }
  return has_key;
}

// #R020: Return caller-provided default for missing fields.
std::string OutlookJsonObject::stringFieldOrDefault(const std::string &key, std::string_view default_value) const
{
  std::string value(default_value);
  std::unordered_map<std::string, std::string>::const_iterator iterator = string_fields_.find(key);
  if (iterator != string_fields_.end())
  {
    value = iterator->second;
  }
  return value;
}

// #R050: Store attachment identity/name/type/size as immutable attachment state.
OutlookAttachment::OutlookAttachment(
    std::string attachment_id,
    std::string file_name,
    std::string content_type,
    int size_in_bytes)
    : attachment_id_(std::move(attachment_id)),
      file_name_(std::move(file_name)),
      content_type_(std::move(content_type)),
      size_in_bytes_(size_in_bytes)
{
}

// #R050: Expose attachment id through a read-only accessor.
const std::string &OutlookAttachment::attachmentId() const
{
  const std::string &value = attachment_id_;
  return value;
}

// #R050: Expose attachment filename through a read-only accessor.
const std::string &OutlookAttachment::fileName() const
{
  const std::string &value = file_name_;
  return value;
}

// #R050: Expose attachment content type through a read-only accessor.
const std::string &OutlookAttachment::contentType() const
{
  const std::string &value = content_type_;
  return value;
}

// #R050: Expose attachment byte size through a read-only accessor.
int OutlookAttachment::sizeInBytes() const
{
  int size_in_bytes = size_in_bytes_;
  return size_in_bytes;
}

// #R025: Materialize Outlook mailcart entities from JSON fields with default-empty fallback.
OutlookMailcart::OutlookMailcart(const OutlookJsonObject &json_object) noexcept(false)
    : Mailcart(
          json_object.stringFieldOrDefault("sender", ""),
          json_object.stringFieldOrDefault("recipient", ""),
          json_object.stringFieldOrDefault("subject", ""),
          BuildMimeContentFromJson(json_object)),
      message_id_(json_object.stringFieldOrDefault("id", "")),
      received_at_(json_object.stringFieldOrDefault("receivedAt", "")),
      body_text_(json_object.stringFieldOrDefault("bodyText", "")),
      body_html_(json_object.stringFieldOrDefault("bodyHtml", "")),
      attachments_(BuildAttachmentsFromJson(json_object))
{
}

// #R030: Expose Outlook-specific metadata through read-only accessors.
const std::string &OutlookMailcart::messageId() const
{
  const std::string &value = message_id_;
  return value;
}

// #R030: Expose received-at timestamp through a read-only accessor.
const std::string &OutlookMailcart::receivedAt() const
{
  const std::string &value = received_at_;
  return value;
}

// #R030: Expose text body through a read-only accessor.
const std::string &OutlookMailcart::bodyText() const
{
  const std::string &value = body_text_;
  return value;
}

// #R030: Expose HTML body through a read-only accessor.
const std::string &OutlookMailcart::bodyHtml() const
{
  const std::string &value = body_html_;
  return value;
}

// #R030: Expose attachments through a read-only accessor.
const std::vector<OutlookAttachment> &OutlookMailcart::attachments() const
{
  const std::vector<OutlookAttachment> &value = attachments_;
  return value;
}

// #R035: Report stable Outlook mailcart type identifier.
std::string OutlookMailcart::type() const
{
  std::string outlook_type = "outlook_mailcart";
  return outlook_type;
}
