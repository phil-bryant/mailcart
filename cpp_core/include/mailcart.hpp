#pragma once
#include "mime_content.hpp"
#include <string>

// #R001: Declare the Mailcart entity interface (constructors, read-only accessors, normalized mutators, and type()).
class Mailcart
{ public:
  Mailcart(std::string sender, std::string recipient, std::string subject, std::string body);
  Mailcart(std::string sender, std::string recipient, std::string subject, MimeContent mime_content);
  virtual ~Mailcart();
  [[nodiscard]] const std::string &sender() const;
  [[nodiscard]] const std::string &recipient() const;
  [[nodiscard]] const std::string &subject() const;
  [[nodiscard]] const std::string &body() const;
  [[nodiscard]] const MimeContent &mimeContent() const;
  virtual void SetSubject(std::string subject);
  virtual void SetBody(std::string body);
  virtual void SetMimeContent(MimeContent mime_content);
  [[nodiscard]] virtual std::string type() const;

  private:
  std::string sender_;
  std::string recipient_;
  std::string subject_;
  MimeContent mime_content_;
};
