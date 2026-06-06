#pragma once
#include <string>

// #R001: Declare the MimeContent value type interface (content-type/content constructor, read-only accessors, plain-text/HTML predicates, mutators, and PlainText/Html factories).
class MimeContent
{ public:
  MimeContent(std::string content_type, std::string content);
  [[nodiscard]] const std::string &contentType() const;
  [[nodiscard]] const std::string &content() const;
  [[nodiscard]] bool isPlainText() const;
  [[nodiscard]] bool isHtml() const;
  [[nodiscard]] bool empty() const;
  void SetContentType(std::string content_type);
  void SetContent(std::string content);
  [[nodiscard]] static MimeContent PlainText(std::string content);
  [[nodiscard]] static MimeContent Html(std::string content);

  private:
  std::string content_type_;
  std::string content_;
};
